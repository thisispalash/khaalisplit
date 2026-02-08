// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {khaaliSplitFriends} from "../src/khaaliSplitFriends.sol";
import {khaaliSplitGroups} from "../src/khaaliSplitGroups.sol";
import {khaaliSplitExpenses} from "../src/khaaliSplitExpenses.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeCore
 * @notice Upgrades Friends, Groups, and Expenses proxies to new implementations
 *         that include backend relay functions (*For pattern).
 *
 * @dev Required environment variables:
 *   - DEPLOYER_PRIVATE_KEY: Private key for the owner EOA (must be proxy owner)
 *   - BACKEND_ADDRESS: Backend/relayer address to set on Groups and Expenses
 *   - FRIENDS_PROXY: Address of the khaaliSplitFriends proxy
 *   - GROUPS_PROXY: Address of the khaaliSplitGroups proxy
 *   - EXPENSES_PROXY: Address of the khaaliSplitExpenses proxy
 *
 * Usage:
 *   forge script script/UpgradeCore.s.sol:UpgradeCore --rpc-url sepolia --broadcast --verify
 */
contract UpgradeCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address backendAddress = vm.envAddress("BACKEND_ADDRESS");
        address friendsProxy = vm.envAddress("FRIENDS_PROXY");
        address groupsProxy = vm.envAddress("GROUPS_PROXY");
        address expensesProxy = vm.envAddress("EXPENSES_PROXY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new implementations
        address newFriendsImpl = address(new khaaliSplitFriends());
        console.log("New Friends impl:", newFriendsImpl);

        address newGroupsImpl = address(new khaaliSplitGroups());
        console.log("New Groups impl:", newGroupsImpl);

        address newExpensesImpl = address(new khaaliSplitExpenses());
        console.log("New Expenses impl:", newExpensesImpl);

        // 2. Upgrade proxies (order matters: Friends -> Groups -> Expenses)
        UUPSUpgradeable(friendsProxy).upgradeToAndCall(newFriendsImpl, "");
        console.log("Friends proxy upgraded");

        UUPSUpgradeable(groupsProxy).upgradeToAndCall(newGroupsImpl, "");
        console.log("Groups proxy upgraded");

        UUPSUpgradeable(expensesProxy).upgradeToAndCall(newExpensesImpl, "");
        console.log("Expenses proxy upgraded");

        // 3. Set backend on Groups and Expenses (Friends already has one)
        khaaliSplitGroups(groupsProxy).setBackend(backendAddress);
        console.log("Groups backend set:", backendAddress);

        khaaliSplitExpenses(expensesProxy).setBackend(backendAddress);
        console.log("Expenses backend set:", backendAddress);

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("Friends proxy:", friendsProxy, "-> impl:", newFriendsImpl);
        console.log("Groups proxy:", groupsProxy, "-> impl:", newGroupsImpl);
        console.log("Expenses proxy:", expensesProxy, "-> impl:", newExpensesImpl);
    }
}
