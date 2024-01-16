// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

struct TokenInfo {
  address owner;
  uint256 ownerTokenIdsIndex;
  uint256 stakedTokenAmount;
  uint256 accuReward; // accumulated reward
  address approved;
}


struct ReceiptTokenStorage {
  uint256 accuTotalReward; // total accumulated rewards
  uint256 tokenIdNum;
  string baseNFTURI;
  mapping(uint256 => TokenInfo) tokenInfo;
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
}