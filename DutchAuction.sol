// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
/// @title Clock Auction Contract (Dutch Auction)
/// @author J U D E  B R A D B U R Y  A N D  S T E P H A N O  V O U R L A M I S
/// @notice This contract implements an NFT clock auction, which acts as a dutch auction for decreasing price p/ time units

contract DutchAuction is AccessControl, Pausable, ERC721Holder  {

    /// Struct creation:
    /// @notice Represents an auction on an NFT
    struct Auction {
        // Current owner of NFT
        address seller;
        // Price (in wei) at beginning of auction
        uint128 startingPrice;
        // Price (in wei) at end of auction
        uint128 endingPrice;
        // Duration (in seconds) of auction
        uint64 duration;
        // Time when auction started
        // NOTE: 0 if this auction has been concluded
        uint64 startedAt;
    }

    // Global Storage:

    // truthy value for those on greenlist
    uint8 constant ON_GREENLIST = 1;

    /// @notice whitelist as a mapping of user addresses to number of NFTs owned to limit number that can be bought from the genesis set per user. 
    mapping (address => uint8) public greenList;

    /// @notice mapping of auctions
    mapping (uint256 => Auction) public auctions;

    /// @notice for storing the address of the NFT contract
    address public NFTContractAddress;
    
    // Constructor:
    constructor(address _speciesNFT) {
        // grant admin role to the deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        NFTContractAddress = _speciesNFT;
    }

    // Event Definitions:

    /// @dev auction created event
    event AuctionCreated(
        uint256 indexed _tokenId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        address _seller
    );

    /// @dev auction bidded on successfully (sold)
    event AuctionSuccessful(
        uint256 indexed _tokenId,
        uint256 _totalPrice,
        address _winner
    );

    /// @dev auction cancelled
    event AuctionCancelled(
        uint256 indexed _tokenId
    );

    // Modifiers:

    // Modifiers to check that inputs can be safely stored with a certain
    // number of bits. We use constants and multiple modifiers to save gas.
    // these were inspired by the same functions in the Axie Clock Auction contract
    modifier canBeStoredWith64Bits(uint256 _value) {
        require(_value <= 18446744073709551615);
        _;
    }

    modifier canBeStoredWith128Bits(uint256 _value) {
        require(_value < 340282366920938463463374607431768211455);
        _;
    }

    // Functions:

    /// @dev fallback logic
    fallback () external {}
    
    /**
    * @notice this function sets the contract address of the NFTs that are auctioned.
    */
    function setNFTContract(address newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NFTContractAddress = newAddress;
    }

    /**
     * @notice this function handles the logic for a user to purchase an NFT currently being auctioned
     * @param _tokenId token ID
     * @param bidAmount amount paid 
    */
    function bid(uint256 _tokenId, uint256 bidAmount) external payable {
        // Get a reference to the auction struct
        Auction storage _auction = auctions[_tokenId];
        // ensure the auction is currently occuring 
        require(_isOnAuction(_auction), "NFT Not on Auction");

        // ensure the user is on the greenlist
        require(greenList[msg.sender] > 0, "The user is not on the greenlist.");

        
        // ensure the amount bidded is greater than the current price as calculated
        uint256 _price = _getCurrentPrice(_auction);
        require(bidAmount >= _price, "The bid was lower than the price. Reverted.");
        
        // all checks are passed...

        // The bid is good! Remove the auction before sending the fees
        // to the sender so we can't have a reentrancy attack.
        _removeAuction(_tokenId);

        // then transfer the NFT to the user
        IERC721(NFTContractAddress).safeTransferFrom(address(this), msg.sender, _tokenId);

        emit // Tell the world!
        AuctionSuccessful(
            _tokenId,
            _price,
            msg.sender
        );
    }

    /**
    * @notice this function allows for the contract owner/admin to bid in lieu of a fiat payer
    * after recieving payment.
    * @param _tokenId token ID
    * @param _buyer fiat buyer's crypto address
    * @param _bidAmount amount bid on the auction (converted to wei from fiat)
    */
    function fiatBid(uint256 _tokenId, address _buyer, uint256 _bidAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Get a reference to the auction struct
        Auction storage _auction = auctions[_tokenId];
        // ensure the auction is currently occuring 
        require(_isOnAuction(_auction), "NFT Not on Auction");

        // ensure the user is on the greenlist
        require(greenList[_buyer] > 0, "The user is not on the greenlist.");

        
        // ensure the amount bidded is greater than the current price as calculated
        uint256 _price = _getCurrentPrice(_auction);
        require(_bidAmount >= _price, "The bid was lower than the price. Reverted.");

        // all checks are passed...

        // The bid is good! Remove the auction before sending the fees
        // to the sender so we can't have a reentrancy attack.
        _removeAuction(_tokenId);

        // then transfer the NFT to the user
        IERC721(NFTContractAddress).safeTransferFrom(address(this), _buyer, _tokenId);
        
        // Tell the world!
        emit 
        AuctionSuccessful(
            _tokenId,
            _price,
            msg.sender
        );
    }

    /**
     * @notice This function allows an admin to add users to the greenList
     * @param toAdd An array of addresses to add to the greenlist
    */
    function addToGreenList(address[] memory toAdd) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for(uint256 i = 0; i < toAdd.length; i++) {
            greenList[toAdd[i]] = ON_GREENLIST;
        }
    }

    /// @dev Returns auction info for an NFT on auction.
    /// @param _tokenId - ID of NFT on auction.
    function getAuction(
        uint256 _tokenId
    )
        external
        view
        returns (
        address seller,
        uint256 startingPrice,
        uint256 endingPrice,
        uint256 duration,
        uint256 startedAt
        )
    {
        Auction storage _auction = auctions[_tokenId];
        require(_isOnAuction(_auction));
        return (
        _auction.seller,
        _auction.startingPrice,
        _auction.endingPrice,
        _auction.duration,
        _auction.startedAt
        );
    }

    /**
    * @notice withdraws the balance of the smart contract to the given admin address
    * @param admin admin address to send funds
    */
    function withdraw(address admin) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(admin).transfer(address(this).balance);
    }

    /**
    * @notice from axie - computes the price of an auction based on the other parameters
    * @param _startingPrice the price at the beginning of the clock auction
    * @param _endingPrice the price at the end of the clock auction
    * @param _duration the duration of the clock auction
    * @param _secondsPassed
    */
    /// @dev Computes the current price of an auction. Factored out
    ///  from _currentPrice so we can run extensive unit tests.
    ///  When testing, make this function external and turn on
    ///  `Current price computation` test suite.
    function _computeCurrentPrice(
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration,
        uint256 _secondsPassed
    )
        internal
        pure
        returns (uint256)
    {
        // NOTE: We don't use SafeMath (or similar) in this function because
        //  all of our external functions carefully cap the maximum values for
        //  time (at 64-bits) and currency (at 128-bits). _duration is
        //  also known to be non-zero (see the require() statement in
        //  _addAuction())
        if (_secondsPassed >= _duration) {
            // We've reached the end of the dynamic pricing portion
            // of the auction, just return the end price.
            return _endingPrice;
        } else {
            // Starting price can be higher than ending price (and often is!), so
            // this delta can be negative.
            int256 _totalPriceChange = int256(_endingPrice) - int256(_startingPrice);

            // This multiplication can't overflow, _secondsPassed will easily fit within
            // 64-bits, and _totalPriceChange will easily fit within 128-bits, their product
            // will always fit within 256-bits.
            int256 _currentPriceChange = _totalPriceChange * int256(_secondsPassed) / int256(_duration);

            // _currentPriceChange can be negative, but if so, will have a magnitude
            // less that _startingPrice. Thus, this result will always end up positive.
            int256 _currentPrice = int256(_startingPrice) + _currentPriceChange;

            return uint256(_currentPrice);
        }
    }

    /// @dev Creates and begins a new auction.
    /// @param _tokenId - ID of token to auction, sender must be owner.
    /// @param _startingPrice - Price of item (in wei) at beginning of auction.
    /// @param _endingPrice - Price of item (in wei) at end of auction.
    /// @param _duration - Length of time to move between starting
    ///  price and ending price (in seconds).
    function createAuction(
        uint256 _tokenId,
        uint256 _startingPrice,
        uint256 _endingPrice,
        uint256 _duration
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        canBeStoredWith128Bits(_startingPrice)
        canBeStoredWith128Bits(_endingPrice)
        canBeStoredWith64Bits(_duration)
    {
        address _seller = msg.sender;
        require(_owns(_seller, _tokenId));
        _escrow(_seller, _tokenId);
        Auction memory _auction = Auction(
        _seller,
        uint128(_startingPrice),
        uint128(_endingPrice),
        uint64(_duration),
        uint64(block.timestamp)
        );
        _addAuction(
        _tokenId,
        _auction,
        _seller
        );
    }
    
    /// @dev Cancels an auction that hasn't been won yet.
    ///  Returns the NFT to original owner.
    /// @notice This is a state-modifying function that can
    ///  be called while the contract is paused.
    /// @param _tokenId - ID of token on auction
    function cancelAuction(uint256 _tokenId) external {
        Auction storage _auction = auctions[_tokenId];
        require(_isOnAuction(_auction));
        require(msg.sender == _auction.seller);
        _cancelAuction(_tokenId, _auction.seller);
    }

    /// @dev Returns current price of an NFT on auction. Broken into two
    ///  functions (this one, that computes the duration from the auction
    ///  structure, and the other that does the price computation) so we
    ///  can easily test that the price computation works correctly.
    function _getCurrentPrice(
        Auction storage _auction
    )
        internal
        view
        returns (uint256)
    {
        uint256 _secondsPassed = 0;

        // A bit of insurance against negative values (or wraparound).
        // Probably not necessary (since Ethereum guarantees that the
        // now variable doesn't ever go backwards).
        if (block.timestamp > _auction.startedAt) {
        _secondsPassed = block.timestamp - _auction.startedAt;
        }

        return _computeCurrentPrice(
        _auction.startingPrice,
        _auction.endingPrice,
        _auction.duration,
        _secondsPassed
        );
    }

    /// @dev Returns the current price of an auction.
    /// @param _tokenId - ID of the token price we are checking.
    function getCurrentPrice(
        uint256 _tokenId
    )
        external
        view
        returns (uint256)
    {
        Auction storage _auction = auctions[_tokenId];
        require(_isOnAuction(_auction));
        return _getCurrentPrice(_auction);
    }

    /// @dev Adds an auction to the list of open auctions. Also fires the
    ///  AuctionCreated event.
    /// @param _tokenId The ID of the token to be put on auction.
    /// @param _auction Auction to add.
    function _addAuction(
        uint256 _tokenId,
        Auction memory _auction,
        address _seller
    )
        internal
    {
        // Require that all auctions have a duration of
        // at least one minute. (Keeps our math from getting hairy!)
        require(_auction.duration >= 1 minutes);

        auctions[_tokenId] = _auction;

        emit AuctionCreated(
        _tokenId,
        uint256(_auction.startingPrice),
        uint256(_auction.endingPrice),
        uint256(_auction.duration),
        _seller
        );
    }

    /// @dev Returns true if the NFT is on auction.
    /// @param _auction - Auction to check.
    function _isOnAuction(Auction storage _auction) internal view returns (bool) {
        return (_auction.startedAt > 0);
    }

    /// @dev Returns true if the claimant owns the token.
    /// @param _claimant - Address claiming to own the token.
    /// @param _tokenId - ID of token whose ownership to verify.
    function _owns(address _claimant, uint256 _tokenId) internal view returns (bool) {
        return (IERC721(NFTContractAddress).ownerOf(_tokenId) == _claimant);
    }

    /// @dev Removes an auction from the list of open auctions.
    /// @param _tokenId - ID of NFT on auction.
    function _removeAuction(uint256 _tokenId) internal {
        delete auctions[_tokenId];
    }

    /// @dev Cancels an auction unconditionally.
    function _cancelAuction(uint256 _tokenId, address _seller) internal {
        _removeAuction(_tokenId);
        IERC721(NFTContractAddress).safeTransferFrom(address(this), _seller, _tokenId);
        emit AuctionCancelled(_tokenId);
    }

    /// @dev Escrows the NFT, assigning ownership to this contract.
    /// Throws if the escrow fails.
    /// @param _owner - Current owner address of token to escrow.
    /// @param _tokenId - ID of token whose approval to verify.
    function _escrow(address _owner, uint256 _tokenId) internal {
        // It will throw if transfer fails
        IERC721(NFTContractAddress).safeTransferFrom(_owner, address(this), _tokenId);
    }
}