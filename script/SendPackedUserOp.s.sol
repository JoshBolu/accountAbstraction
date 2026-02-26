// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() public {
        address transferTo = 0x02e2EEDF19a3d98D4677c84Ac5BD1BdFF51b7007;
        HelperConfig helperConfig = new HelperConfig();
        address dest = helperConfig.getConfig().usdc; // Arbitrum mainnet USDC address
        uint256 value = 0;
        // we get this after we have deployed the minimal account contract
        address minimalAccountAddress = 0x6bF86f3717c0D04D6AC3B3c01f20167179706a3b;
        // we are transferring .003 USDC which is 3e6 because USDC has 6 decimals
        bytes memory functionData = abi.encodeWithSelector(IERC20.transfer.selector, transferTo, 3e3);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            generateSignedUserOperation(executeCallData, helperConfig.getConfig(), minimalAccountAddress);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(helperConfig.getConfig().account));
        vm.stopBroadcast();
    }

    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory config,
        address minimalAccount
    ) public view returns (PackedUserOperation memory) {
        // 1. Generate unsigned user operation
        uint256 nonce = IEntryPoint(config.entryPoint).getNonce(minimalAccount, 0);
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, minimalAccount, nonce);
        // 2. Get user operation
        // the userOpHash is what the entryPoint will use to verify the signature and also to prevent replay attacks by making sure the nonce is correct
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        // we need to sign the userOpHash in EIP-191 format which is what the toEthSignedMessageHash does
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 anvilDefaultKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        // 3. Sign it
        if (block.chainid == 31337) {
            (v, r, s) = vm.sign(anvilDefaultKey, digest);
        } else {
            (v, r, s) = vm.sign(config.account, digest);
        }
        userOp.signature = abi.encodePacked(r, s, v); // note the change in order
        return userOp;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
