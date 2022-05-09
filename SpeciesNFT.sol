// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";



/// @title SPECIES NFT DRAFT CONTRACT
/// @author JUDE BRADBURY w/ OPENZEPPELIN WIZARD
/// @notice this is essentially the basic NFT contract to be utilised by the sales handler 

contract SpeciesNFT is ERC721, ERC721Enumerable, AccessControl {

    using EnumerableSet for EnumerableSet.UintSet;

    /**
        @notice STORAGE VARIABLES
    */

    // minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Mapping from holder address to their (enumerable) set of owned tokens
    mapping (address => EnumerableSet.UintSet) private _holderTokens;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    // Enumerable mapping from token ids to their owners
    // EnumerableMap.UintToAddressMap private _tokenOwners;
    // use mapping for now
    mapping (uint256 => address) private _tokenOwners;

    string private _uri;

    constructor(string memory uri) ERC721("SpeciesNFT", "SNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _uri = uri;
    }

    function safeMint(address to, uint256 tokenId) external onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
        _holderTokens[from].remove(tokenId); // remove the token from the set of the sender
        _holderTokens[to].add(tokenId); // add the token to the set of the sender
        _tokenOwners[tokenId] = to;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
    * @notice essentially the same as balanceOf but using the 
    * @param owner of the tokens to query
    */
    function getNumTokens(address owner) external view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");

        return _holderTokens[owner].length();
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwner}.
     * @notice returns an array of tokens owned by the input address
     * @param owner the address whose tokens to return
     * @return tokens owned by the owner
     */
    function getOwnerTokens(address owner) external view returns (uint256[] memory) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        uint256[] memory tokens = new uint256[](_holderTokens[owner].length());
        for(uint i=0; i<_holderTokens[owner].length(); i++) {
            tokens[i] = _holderTokens[owner].at(i);
        }
        return tokens;
    }

    /**
    * @notice this function returns the owner of a token.
    * @param tokenId the id of the token
    */
    function getTokenOwner(uint256 tokenId) external view returns (address) {
        return _tokenOwners[tokenId];
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _uri;
    }
}