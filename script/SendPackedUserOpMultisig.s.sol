// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity 0.8.31;

import {Script} from "forge-std/Script.sol";
import {PackedUserOperation} from "../lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {HelperConfigMultisig} from "script/HelperConfigMultisig.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MinimalAccountMultiSig} from "../src/ethereum/MinimalAccountMultiSig.sol";

contract SendPackedUserOpMultisig is Script {
    using MessageHashUtils for bytes32;

    uint256[] anvildefaultkeys = [
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
        0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
    ];

    bytes[] signaturesArray;

    function run() public {
        address transferTo = 0x02e2EEDF19a3d98D4677c84Ac5BD1BdFF51b7007;
        HelperConfigMultisig helperConfig = new HelperConfigMultisig();
        address dest = helperConfig.getConfig().usdc; // Arbitrum mainnet USDC address
        uint256 value = 0;
        address minimalAccountMultisig = 0x6bF86f3717c0D04D6AC3B3c01f20167179706a3b; // we get this after we have deployed the minimal account multisig contract
        // we are transferring .003 USDC which is 3e6 because USDC has 6 decimals
        bytes memory functionData = abi.encodeWithSelector(IERC20.transfer.selector, transferTo, 3e3);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccountMultiSig.execute.selector, dest, value, functionData);
        PackedUserOperation memory userOp =
            generateSignedOperation(executeCallData, helperConfig.getConfig(), minimalAccountMultisig);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startBroadcast();
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(helperConfig.getConfig().accounts[0]));
        vm.stopBroadcast();
    }

    function generateSignedOperation(
        bytes memory callData,
        HelperConfigMultisig.NetworkConfig memory config,
        address minimalAccountMultisig
    ) public returns (PackedUserOperation memory) {
        uint256 nonce = IEntryPoint(config.entryPoint).getNonce(minimalAccountMultisig, 0);
        PackedUserOperation memory userOp = _generateUnsignedUserOperation(callData, minimalAccountMultisig, nonce);
        bytes32 userOpHash = IEntryPoint(config.entryPoint).getUserOpHash(userOp);
        // we need to sign the userOpHash in EIP-191 format which is what the toEthSignedMessageHash does
        bytes32 digest = userOpHash.toEthSignedMessageHash();
        uint8 v;
        bytes32 r;
        bytes32 s;
        // we are simulating 5 out of 5 signatures from the burner accounts
        for (uint256 i = 0; i < 5; i++) {
            if (block.chainid == 31337) {
                (v, r, s) = vm.sign(anvildefaultkeys[i], digest);
            } else {
                (v, r, s) = vm.sign(config.accounts[i], digest);
            }

            bytes memory signature = bytes.concat(userOp.signature, abi.encodePacked(r, s, v));

            signaturesArray.push(signature);
        }
        userOp.signature = _concatSortedSignatures(config.accounts, signaturesArray);
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

    function _concatSortedSignatures(address[] memory signers, bytes[] memory signatures)
        internal
        pure
        returns (bytes memory)
    {
        uint256 n = signers.length;
        require(n == signatures.length, "len mismatch");

        // sort by signer address (ascending)
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = i + 1; j < n; j++) {
                if (signers[j] < signers[i]) {
                    address tmpAddr = signers[i];
                    signers[i] = signers[j];
                    signers[j] = tmpAddr;

                    bytes memory tmpSig = signatures[i];
                    signatures[i] = signatures[j];
                    signatures[j] = tmpSig;
                }
            }
        }

        // concat in sorted order
        bytes memory combined;
        for (uint256 k = 0; k < n; k++) {
            combined = bytes.concat(combined, signatures[k]);
        }
        return combined;
    }
}
