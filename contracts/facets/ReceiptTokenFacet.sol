//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.23;

import "hardhat/console.sol";

import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";
import {IERC721Receiver} from "../interfaces/IERC721Receiver.sol";
import {Strings} from "../libraries/Strings.sol";
import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {SafeERC20} from "../libraries/SafeERC20.sol";
import {LibReceiptToken, ReceiptTokenStorage} from "../libraries/LibReceiptToken.sol";


contract ReceiptTokenFacet is IERC721, IERC721Errors {
  FarmFacet immutable StakingContract = 0x1fE64677Ab1397e20A1211AFae2758570fEa1B8c;
  address immutable GLTRTradeStakingContract;
  IERC20 immutable StakingToken;
  IERC20 immutable RewardToken;
  string immutable NftName;
  string immutable NftSymbol;
  AppStorage internal s;

  constructor(string memory _nftName, string memory _nftSymbol, address _stakingToken) {
    NftName = _nftName;
    NftSymbol = _nftSymbol; 
    GLTRTradeStakingContract = msg.sender;
    StakingToken = stakingToken;
    RewardToken = StakingContract.rewardToken();
  }

  

  function rewardToken() external view returns(address) {
    return RewardToken;
  }

  function totalReward() internal view returns(uint256) {
    return RewardToken.balanceOf(address(this));
  }

  function deposit(uint256 _amount) external {
    uint256 contractBalance = RewardToken.balanceOf(address(this));


  }
  
  function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
        return _interfaceID == 0x01ffc9a7  //ERC165
            || _interfaceID == 0x80ac58cd  //ERC721
            || _interfaceID == 0x5b5e139f;  //ERC721Metadata
  }

  

  /// @notice A descriptive name for a collection of NFTs in this contract
  function name() external view returns (string memory name_) {
    return nftName;
  }

  /// @notice An abbreviated name for NFTs in this contract
  function symbol() external view returns (string memory symbol_) {
    return nftSymbol;
  }

  function setTokenBaseURI(string calldata _url) external onlyGLTRTradeStaking() {
    s.baseNFTURI = _url;
  }

  function ownerExistsAndReturnIt(uint256 _tokenId) internal view returns (address) {
    address owner = s.tokenInfo[_tokenId].owner;
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
     return string.concat(s.baseNFTURI, Strings.toString(_tokenId));
  }

  /**
    * @dev Returns the number of tokens in ``owner``'s account.
    */
  function balanceOf(address _owner) external view returns (uint256 balance_) {
    return s.userTokenIds[_owner].length;
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
     * This function is from OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/ERC721.sol)     
     * @dev Private function to invoke {IERC721Receiver-onERC721Received} on a target address. This will revert if the
     * recipient doesn't accept the token transfer. The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     */
  function checkOnERC721Received(address _from, address _to, uint256 _tokenId, bytes calldata _data) private {
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, _from, _tokenId, _data) returns (bytes4 retval_) {
                if (retval_ != IERC721Receiver.onERC721Received.selector) {
                    revert ERC721InvalidReceiver(_to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert ERC721InvalidReceiver(_to);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
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
    checkOnERC721Received(_from, _to, _tokenId, _data);
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
    checkOnERC721Received(_from, _to, _tokenId, "");
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

  function isAuthorized(address _owner, address _spender, uint256 _tokenId) {
    return msg.sender == _owner || msg.sender == GLTRTradeStakingContract || internalIsApprovedForAll(owner, msg.sender) || s.tokenInfo.approved == msg.sender;
  }

  function internalTransferFrom(address _from, address _to, uint256 _tokenId) internal {
    if(_to == address(0)) {
      revert ERC721InvalidReceiver(address(0));
    }
    address owner = ownerExistsAndReturnIt(_tokeinId);
    if(owner != _from) {
      revert ERC721IncorrectOwner(_from, tokenId, owner);
    }
    if(!isAuthorized(owner, msg.sender, _tokenId)) {
       revert ERC721InsufficientApproval(msg.sender, _tokenId);
    }
    uint256 lastIndex = s.ownerTokenIds[owner].length - 1;
    uint256 currentIndex = s.tokenInfo[_tokenId].ownerTokenIdsIndex;
    if(lastIndex != currentIndex) {      
      uint256 lastTokenId = s.ownerTokenIds[owner][lastIndex];
      s.ownerTokenIds[owner][currentIndex] = lastTokenId;
      s.tokenInfo[lastTokenId].ownerTokenIdsIndex = currentIndex;
    }
    s.ownerTokenIds[owner].pop();

    s.tokenInfo[_tokenId].approved = address(0);
    s.tokenInfo[_tokenId].owner = _to;
    s.tokenInfo[_tokenId].ownerTokenIdsIndex = s.ownerTokenIds[_to].length;
    s.ownerTokenIds[_to].push(_tokenId);

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
    if(msg.sender != owner && !s.operators[owner][msg.sender]) {
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
    if(operator == address(0)) {
      revert ERC721InvalidOperator(operator);
    }
    s.operators[msg.sender][_operator] _approved;
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
    returnOwner(_tokenId);
    return s.tokenInfo[_tokenId].approved;
  }

  /**
    * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
    *
    * See {setApprovalForAll}
    */
  function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
    return internalIsApprovedForAll(_owner, _operator);
  }

  function internalIsApprovedForAll(address _owner, address _operator) internal view returns (bool) {
    return _operator == s.operators[_owner][_operator];
  }


    /// @notice Enumerate NFTs assigned to an owner
    /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
    ///  `_owner` is the zero address, representing invalid NFTs.
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}

