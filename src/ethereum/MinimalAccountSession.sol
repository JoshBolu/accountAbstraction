// SPDX-License-Identifier:MIT SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS, _packValidationData} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

// Minimal AA account with session key + expiry.
contract MinimalAccountSession is IAccount, Ownable {
    /*/////////////////////////////////////////////////////////
                            ERRORS
    /////////////////////////////////////////////////////////*/
    error MinimalAccountSession__NotFromEntryPoint();
    error MinimalAccountSession__NotFromEntryPointOrOwner();
    error MinimalAccountSession__CallFailed(bytes);
    error MinimalAccountSession__InvalidSessionKey();

    /*/////////////////////////////////////////////////////////
                        STATE VARIABLES
    /////////////////////////////////////////////////////////*/
    IEntryPoint private immutable I_ENTRY_POINT;
    address public sessionKey;
    uint48 public sessionValidUntil;
    string public sessionProvider;

    constructor(address entryPoint, string memory providerName) Ownable(msg.sender) {
        I_ENTRY_POINT = IEntryPoint(entryPoint);
        sessionProvider = providerName;
    }

    receive() external payable {}

    modifier requireFromEntryPoint() {
        _requireFromEntryPoint();
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        _requireFromEntryPointOrOwner();
        _;
    }

    /*/////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////*/

    function setSessionKey(address key, uint48 validUntil) external onlyOwner {
        if (key == address(0)) revert MinimalAccountSession__InvalidSessionKey();
        sessionKey = key;
        sessionValidUntil = validUntil;
    }

    function clearSessionKey() external onlyOwner {
        sessionKey = address(0);
        sessionValidUntil = 0;
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if (!success) {
            revert MinimalAccountSession__CallFailed(result);
        }
    }

    /*/////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    /////////////////////////////////////////////////////////*/

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if (signer == owner()) {
            return SIG_VALIDATION_SUCCESS;
        }
        if (signer == sessionKey && sessionKey != address(0)) {
            return _packValidationData(false, sessionValidUntil, 0);
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
            revert MinimalAccountSession__NotFromEntryPoint();
        }
    }

    function _requireFromEntryPointOrOwner() internal view {
        if (msg.sender != address(I_ENTRY_POINT) && msg.sender != owner()) {
            revert MinimalAccountSession__NotFromEntryPointOrOwner();
        }
    }

    /*/////////////////////////////////////////////////////////
                            GETTERS
    /////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(I_ENTRY_POINT);
    }
}
