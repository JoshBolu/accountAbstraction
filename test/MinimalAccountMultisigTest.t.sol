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

    uint256 constant AMOUNT = 1e18;
    address randomUser = makeAddr("randomUser");
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

    function testValidationOfUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccountMultisig)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccountMultisig), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccountMultiSig.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOpMultiSig.generateSignedOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccountMultisig)
        );
        bytes32 userOpHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        uint256 missingAccountFunds = 1e18;

        // Act
        vm.startPrank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccountMultisig.validateUserOp(packedUserOp, userOpHash, missingAccountFunds);

        // Assert
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommand() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccountMultisig)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData =
            abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccountMultisig), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccountMultiSig.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOpMultiSig.generateSignedOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccountMultisig)
        );

        vm.deal(address(minimalAccountMultisig), AMOUNT);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        // Act
        vm.startPrank(randomUser, randomUser);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomUser));
        vm.stopPrank();

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccountMultisig)), AMOUNT);
    }
}
