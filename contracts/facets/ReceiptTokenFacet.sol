// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "hardhat/console.sol";

import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";
import {Strings} from "../libraries/Strings.sol";
import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibReceiptToken, ReceiptTokenStorage} from "../libraries/LibReceiptToken.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";


contract ReceiptTokenFacet is IERC721, IERC721Errors {
  string internal constant NftName = "GLTR Staking Receipt Token";  
  string internal constant NftSymbol = "GSRT";
    
  function supportsInterface(bytes4 _interfaceID) external pure returns (bool) {
    return _interfaceID == 0x01ffc9a7  //ERC165
      || _interfaceID == 0x80ac58cd  //ERC721
      || _interfaceID == 0x5b5e139f;  //ERC721Metadata
  }

  

  /// @notice A descriptive name for a collection of NFTs in this contract
  function name() external pure returns (string memory name_) {
    return NftName;
  }

  /// @notice An abbreviated name for NFTs in this contract
  function symbol() external pure returns (string memory symbol_) {
    return NftSymbol;
  }

  function setTokenBaseURI(string calldata _url) external {
    LibDiamond.enforceIsContractOwner();
    LibReceiptToken.diamondStorage().baseNFTURI = _url;
  }

  function ownerExistsAndReturnIt(uint256 _tokenId) internal view returns (address) {
    address owner = LibReceiptToken.diamondStorage().tokenInfo[_tokenId].owner;
    if (owner == address(0)) {
        revert ERC721NonexistentToken(_tokenId);
    }
    return owner;
  }

  /// @notice A distinct Uniform Resource Identifier (URI) for a given asset.
  /// @dev Throws if `_tokenId` is not a valid NFT. URIs are defined in RFC
  ///  3986. The URI may point to a JSON file that conforms to the "ERC721
  ///  Metadata JSON Schema".
  function tokenURI(uint256 _tokenId) external view returns (string memory) {
     ownerExistsAndReturnIt(_tokenId);
     return string.concat(LibReceiptToken.diamondStorage().baseNFTURI, Strings.toString(_tokenId));
  }

  /**
    * @dev Returns the number of tokens in ``owner``'s account.
    */
  function balanceOf(address _owner) external view returns (uint256 balance_) {
    if (_owner == address(0)) {
      revert ERC721InvalidOwner(address(0));
    }
    return LibReceiptToken.diamondStorage().ownerTokenIds[_owner].length;
  }

  /**
    * @dev Returns the owner of the `tokenId` token.
    *
    * Requirements:
    *
    * - `tokenId` must exist.
    */
  function ownerOf(uint256 _tokenId) external view returns (address owner_){
    return ownerExistsAndReturnIt(_tokenId);
  }



  /**
    * @dev Safely transfers `tokenId` token from `from` to `to`.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must exist and be owned by `from`.
    * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
    * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
    *   a safe transfer.
    *
    * Emits a {Transfer} event.
    */
  function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata _data) external {
    internalTransferFrom(_from, _to, _tokenId);
    LibReceiptToken.checkOnERC721Received(_from, _to, _tokenId, _data);
  }

  /**
    * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
    * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must exist and be owned by `from`.
    * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
    *   {setApprovalForAll}.
    * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
    *   a safe transfer.
    *
    * Emits a {Transfer} event.
    */
  function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
    internalTransferFrom(_from, _to, _tokenId);
    LibReceiptToken.checkOnERC721Received(_from, _to, _tokenId, ""); 
  }

  /**
    * @dev Transfers `tokenId` token from `from` to `to`.
    *
    * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
    * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
    * understand this adds an external call which potentially creates a reentrancy vulnerability.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must be owned by `from`.
    * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
    *
    * Emits a {Transfer} event.
    */
  function transferFrom(address _from, address _to, uint256 _tokenId) external {
    internalTransferFrom(_from, _to, _tokenId);

  }

  

  function internalTransferFrom(address _from, address _to, uint256 _tokenId) internal {
    if(_to == address(0)) {
      revert ERC721InvalidReceiver(address(0));
    }
    address owner = ownerExistsAndReturnIt(_tokenId);
    if(owner != _from) {
      revert ERC721IncorrectOwner(_from, _tokenId, owner);
    }
    if(!LibReceiptToken.isAuthorized(owner, msg.sender, _tokenId)) {
       revert ERC721InsufficientApproval(msg.sender, _tokenId);
    }
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    uint256 lastIndex = rt.ownerTokenIds[owner].length - 1;
    uint256 currentIndex = rt.tokenInfo[_tokenId].ownerTokenIdsIndex;
    if(lastIndex != currentIndex) {      
      uint256 lastTokenId = rt.ownerTokenIds[owner][lastIndex];
      rt.ownerTokenIds[owner][currentIndex] = lastTokenId;
      rt.tokenInfo[lastTokenId].ownerTokenIdsIndex = currentIndex;
    }
    rt.ownerTokenIds[owner].pop();

    rt.tokenInfo[_tokenId].approved = address(0);
    rt.tokenInfo[_tokenId].owner = _to;
    rt.tokenInfo[_tokenId].ownerTokenIdsIndex = rt.ownerTokenIds[_to].length;
    rt.ownerTokenIds[_to].push(_tokenId);

    emit Transfer(_from, _to, _tokenId);
  }



  /**
    * @dev Gives permission to `to` to transfer `tokenId` token to another account.
    * The approval is cleared when the token is transferred.
    *
    * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
    *
    * Requirements:
    *
    * - The caller must own the token or be an approved operator.
    * - `tokenId` must exist.
    *
    * Emits an {Approval} event.
    */
  function approve(address _to, uint256 _tokenId) external {
    address owner = ownerExistsAndReturnIt(_tokenId);
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    if(msg.sender != owner && !rt.operators[owner][msg.sender]) {
      revert ERC721InvalidApprover(msg.sender);
    }
    emit Approval(owner, _to, _tokenId);
  }

  /**
    * @dev Approve or remove `operator` as an operator for the caller.
    * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
    *
    * Requirements:
    *
    * - The `operator` cannot be the address zero.
    *
    * Emits an {ApprovalForAll} event.
    */
  function setApprovalForAll(address _operator, bool _approved) external {
    if(_operator == address(0)) {
      revert ERC721InvalidOperator(_operator);
    }
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    rt.operators[msg.sender][_operator] = _approved;
    emit ApprovalForAll(msg.sender, _operator, _approved);
  }

  /**
    * @dev Returns the account approved for `tokenId` token.
    *
    * Requirements:
    *
    * - `tokenId` must exist.
    */
  function getApproved(uint256 _tokenId) external view returns (address operator_) {
    ownerExistsAndReturnIt(_tokenId);
    return LibReceiptToken.diamondStorage().tokenInfo[_tokenId].approved;
  }

  /**
    * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
    *
    * See {setApprovalForAll}
    */
  function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
    return LibReceiptToken.diamondStorage().operators[_owner][_operator];
  }

  /**
    * @dev An `owner`'s token query was out of bounds for `index`.
    *
    * NOTE: The owner being `address(0)` indicates a global out of bounds index.
    */
  error ERC721OutOfBoundsIndex(address owner, uint256 index);  

  /// @notice Enumerate NFTs assigned to an owner
  /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
  ///  `_owner` is the zero address, representing invalid NFTs.
  /// @param _owner An address where we are interested in NFTs owned by them
  /// @param _index A counter less than `balanceOf(_owner)`
  /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
  ///   (sort order not specified)
  function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    if(_index >= rt.ownerTokenIds[_owner].length) {
      revert ERC721OutOfBoundsIndex(_owner, _index);
    }
    return rt.ownerTokenIds[_owner][_index];
  }
}

