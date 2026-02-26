// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {console} from "forge-std/console.sol";

// Minimal multisig AA account. Signatures are 65-byte concatenated (r,s,v) for each owner.
contract MinimalAccountMultiSig is IAccount {
    /*/////////////////////////////////////////////////////////
                            ERRORS
    /////////////////////////////////////////////////////////*/
    error MinimalAccountMultiSig__NotFromEntryPoint();
    error MinimalAccountMultiSig__CallFailed(bytes);
    error MinimalAccountMultiSig__InvalidOwners();
    error MinimalAccountMultiSig__InvalidThreshold();
    error MinimalAccountMultiSig__InvalidSignatures();

    /*/////////////////////////////////////////////////////////
                        STATE VARIABLES
    /////////////////////////////////////////////////////////*/
    IEntryPoint private immutable I_ENTRY_POINT;
    uint256 public immutable THRESHOLD;
    mapping(address => bool) public isOwner;
    address[] public owners;

    constructor(address entryPoint, address[] memory _owners, uint256 _threshold) {
        if (_owners.length == 0) revert MinimalAccountMultiSig__InvalidOwners();
        if (_threshold == 0 || _threshold > _owners.length) {
            revert MinimalAccountMultiSig__InvalidThreshold();
        }
        I_ENTRY_POINT = IEntryPoint(entryPoint);
        THRESHOLD = _threshold;
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            if (owner == address(0) || isOwner[owner]) revert MinimalAccountMultiSig__InvalidOwners();
            isOwner[owner] = true;
            owners.push(owner);
        }
    }

    receive() external payable {}

    modifier requireFromEntryPoint() {
        _requireFromEntryPoint();
        _;
    }

    /*/////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////*/

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignatures(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPoint {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccountMultiSig__CallFailed(result);
        }
    }

    /*/////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////*/

    function _validateSignatures(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        uint256 sigCount = userOp.signature.length / 65;
        console.log("sig count: ", sigCount);
        if (sigCount < THRESHOLD || userOp.signature.length % 65 != 0) {
            return SIG_VALIDATION_FAILED;
        }

        address lastSigner = address(0);
        uint256 validSigners = 0;

        for (uint256 i = 0; i < sigCount; i++) {
            uint256 offset = i * 65;
            bytes calldata sig = userOp.signature[offset:offset + 65];
            address signer = ECDSA.recover(ethSignedMessageHash, sig);
            if (!isOwner[signer]) {
                return SIG_VALIDATION_FAILED;
            }
            // Enforce strictly increasing order to prevent duplicates.
            if (signer <= lastSigner) {
                return SIG_VALIDATION_FAILED;
            }
            lastSigner = signer;
            validSigners++;
            if (validSigners == THRESHOLD) {
                return SIG_VALIDATION_SUCCESS;
            }
        }

        return SIG_VALIDATION_FAILED;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        if (missingAccountFunds != 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    function _requireFromEntryPoint() internal view {
        if (msg.sender != address(I_ENTRY_POINT)) {
            revert MinimalAccountMultiSig__NotFromEntryPoint();
        }
    }

    /*/////////////////////////////////////////////////////////
                            GETTERS
    /////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(I_ENTRY_POINT);
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }
}
