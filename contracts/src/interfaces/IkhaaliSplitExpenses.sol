// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IkhaaliSplitExpenses {
    function expenseCount() external view returns (uint256);
    function getExpense(uint256 expenseId) external view returns (uint256 groupId, address creator, bytes32 dataHash, uint256 timestamp);
    function getGroupExpenses(uint256 groupId) external view returns (uint256[] memory);

    function addExpense(uint256 groupId, bytes32 dataHash, bytes calldata encryptedData) external returns (uint256 expenseId);
    function updateExpense(uint256 expenseId, bytes32 newDataHash, bytes calldata newEncryptedData) external;

    function addExpenseFor(address creator, uint256 groupId, bytes32 dataHash, bytes calldata encryptedData) external returns (uint256 expenseId);
    function updateExpenseFor(address creator, uint256 expenseId, bytes32 newDataHash, bytes calldata newEncryptedData) external;

    function setBackend(address _backend) external;
    function backend() external view returns (address);
}
