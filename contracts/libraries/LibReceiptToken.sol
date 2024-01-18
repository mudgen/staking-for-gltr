// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC721Receiver} from "../interfaces/IERC721Receiver.sol";
import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";

struct TokenInfo {
  address owner;
  uint256 ownerTokenIdsIndex;
  uint256 stakedTokenAmount;  
  address approved;
  uint96 poolId;
  uint256 debt;
}

struct ReceiptTokenStorage {  
  uint256 tokenIdNum;
  string baseNFTURI;
  mapping(uint256 tokenId => TokenInfo) tokenInfo;
  mapping(address owner => uint256[] tokenId) ownerTokenIds;
  mapping(address owner => mapping(address operator => bool)) operators;
}

library LibReceiptToken {
  bytes32 constant RECEIPT_TOKEN_STORAGE_POSITION = keccak256("gltr-receipt-token.storage");
  
  // rt == receipt token
  function diamondStorage() internal pure returns (ReceiptTokenStorage storage rt) {
    bytes32 position = RECEIPT_TOKEN_STORAGE_POSITION;
    assembly {
      rt.slot := position
    }
  }

  function isAuthorized(address _owner, address _spender, uint256 _tokenId) internal view returns(bool){
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    return _spender == _owner || rt.operators[_owner][_spender] || rt.tokenInfo[_tokenId].approved == _spender;
  }

  /**
    * This function is from OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/ERC721.sol)     
    * @dev Private function to invoke {IERC721Receiver-onERC721Received} on a target address. This will revert if the
    * recipient doesn't accept the token transfer. The call is not executed if the target address is not a contract.
    *
    * @param _from address representing the previous owner of the given token ID
    * @param _to target address that will receive the tokens
    * @param _tokenId uint256 ID of the token to be transferred
    * @param _data bytes optional data to send along with the call
    */
  function checkOnERC721Received(address _from, address _to, uint256 _tokenId, bytes memory _data) internal {
    if (_to.code.length > 0) {
      try IERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data) returns (bytes4 retval_) {
        if (retval_ != IERC721Receiver.onERC721Received.selector) {
            revert IERC721Errors.ERC721InvalidReceiver(_to);
        }
      } catch (bytes memory reason) {
        if (reason.length == 0) {
          revert IERC721Errors.ERC721InvalidReceiver(_to);
        } else {
          /// @solidity memory-safe-assembly
          assembly {
            revert(add(32, reason), mload(reason))
          }
        }
      }
    }
  }

  function burn(uint256 _tokenId) internal {
    ReceiptTokenStorage storage rt = LibReceiptToken.diamondStorage();
    TokenInfo storage ti = rt.tokenInfo[_tokenId];
    address owner = ti.owner; 
    uint256 lastIndex = rt.ownerTokenIds[owner].length - 1;
    uint256 currentIndex = rt.tokenInfo[_tokenId].ownerTokenIdsIndex;
    if(lastIndex != currentIndex) {      
      uint256 lastTokenId = rt.ownerTokenIds[owner][lastIndex];
      rt.ownerTokenIds[owner][currentIndex] = lastTokenId;
      rt.tokenInfo[lastTokenId].ownerTokenIdsIndex = currentIndex;
    }
    rt.ownerTokenIds[owner].pop();
    delete rt.tokenInfo[_tokenId];
    emit IERC721.Transfer(owner, address(0), _tokenId);
  }
}