// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccountMultiSig} from "../src/ethereum/MinimalAccountMultiSig.sol";
import {DeployMinimalAccountMultisig} from "../script/DeployMinimalAccountMultisig.s.sol";
import {HelperConfigMultisig} from "../script/HelperConfigMultisig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOpMultisig, PackedUserOperation} from "script/SendPackedUserOpMultisig.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccountMultiSigTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfigMultisig helperConfig;
    MinimalAccountMultiSig minimalAccountMultisig;
    ERC20Mock usdc;
    SendPackedUserOpMultisig sendPackedUserOpMultiSig;

    function setUp() public {
        // Set up any necessary state or contracts before each test
        DeployMinimalAccountMultisig deployMinimalMultisig = new DeployMinimalAccountMultisig();
        (helperConfig, minimalAccountMultisig) = deployMinimalMultisig.deployMinimalAccountMultisig();
        usdc = new ERC20Mock();
        sendPackedUserOpMultiSig = new SendPackedUserOpMultisig();
    }

    function testOwnersDeployedCorrectly() public {
        address[] memory owners = minimalAccountMultisig.getOwners();
        for (uint256 i; i < owners.length; i++) {
            assertEq(owners[i], helperConfig.getConfig().accounts[i]);
        }
        assertEq(owners.length, 5);
    }
}
