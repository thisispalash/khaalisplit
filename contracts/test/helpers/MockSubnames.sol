// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title MockSubnames
 * @notice Minimal mock of khaaliSplitSubnames for testing khaaliSplitReputation.
 *         Implements only the setText() function that the reputation contract calls
 *         for ENS text record syncing.
 *
 * @dev Records all setText calls for test assertions. Does NOT implement the full
 *      IkhaaliSplitSubnames interface — only the function our reputation contract uses.
 */
contract MockSubnames {
    // ──────────────────────────────────────────────
    //  Storage
    // ──────────────────────────────────────────────

    /// @notice Recorded setText calls for test assertions.
    struct SetTextCall {
        bytes32 node;
        string key;
        string value;
    }

    /// @notice All setText calls in order.
    SetTextCall[] public setTextCalls;

    /// @notice On-chain text records: node → key → value (mirrors real subnames behavior).
    mapping(bytes32 => mapping(string => string)) private _texts;

    /// @notice Whether setText should revert (for testing error handling).
    bool public shouldRevert;

    // ──────────────────────────────────────────────
    //  IkhaaliSplitSubnames.setText (mocked)
    // ──────────────────────────────────────────────

    /**
     * @notice Mock setText — records the call and stores the text record.
     */
    function setText(bytes32 node, string calldata key, string calldata value) external {
        if (shouldRevert) revert("MockSubnames: forced revert");

        setTextCalls.push(SetTextCall({node: node, key: key, value: value}));
        _texts[node][key] = value;
    }

    // ──────────────────────────────────────────────
    //  Test Helpers
    // ──────────────────────────────────────────────

    /// @notice Get the total number of setText calls recorded.
    function setTextCallCount() external view returns (uint256) {
        return setTextCalls.length;
    }

    /// @notice Get a specific setText call by index.
    function getSetTextCall(uint256 index) external view returns (bytes32 node, string memory key, string memory value) {
        SetTextCall storage call_ = setTextCalls[index];
        return (call_.node, call_.key, call_.value);
    }

    /// @notice Read a stored text record (mirrors subnames.text()).
    function text(bytes32 node, string calldata key) external view returns (string memory) {
        return _texts[node][key];
    }

    /// @notice Toggle whether setText should revert.
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}
