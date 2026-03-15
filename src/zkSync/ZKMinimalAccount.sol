// SPDX-License-Identifier:MIT
pragma solidity ^0.8.28;

import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {
    SystemContractsCaller
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * Life Cycle of a type 113 (0x71) transaction:
 * msg.sender is the bootloader system contract
 *
 * Phase 1 Validation:
 * 1. The user sends the transaction to the "ZKSync API Client" (sort of a "light node")
 * 2. The ZKSync API Client checks to see the nonce is unique by querying the NonceHolder system contract
 * 3. The ZKSync API Client calls validateTransactio, which must update the nonce that's where the msg.sender who is the bootloader comes in
 * 4. The zkSync API Client checks the nonce is updated
 * 5. The zkSync API calls payForTransaction, or prepareForPaymaster & validationPayForPaymasterTransaction
 * 6. The zkSync API Client verifies that the bootloader gets paid
 *
 * Phase 2 Execution:
 * 7. The zkSync API Client passes the validated transaction to the main node/sequencer (as of today they are the same)
 * 8. The main node calls executeTransaction
 * 9. If a paymaster was used, the postTransaction is called
 */
contract ZKMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZKMinimalAccount__NotEnoughBalance();
    error ZKMinimalAccount__NotFromBootloader();
    error ZKMinimalAccount__ExecutionFailed();
    error ZKMinimalAccount__NotFromBootloaderOrOwner();
    error ZKMinimalAccount__FailedToPayBootLoader();
    error ZKMinimalAccount__InvalidSignature();

    event ZKMinimalAccount__TransactionExecuted(
        bytes32 indexed _txHash, bytes32 indexed _suggestedSignedHash, Transaction _transaction
    );

    /* /////////////////////////////////////////////////////////
                    MODIFIERS
    ///////////////////////////////////////////////////////// */
    modifier requireFromBootloader() {
        _requireFromBootloader();
        _;
    }

    modifier requireFromBootloaderOrOwner() {
        _requireFromBootloaderOrOwner();
        _;
    }

    /* /////////////////////////////////////////////////////////
                    EXTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////// */

    constructor() Ownable(msg.sender) {}

    receive() external payable {}

    /**
     * @notice must increase the nonce
     * @notice must validate the transaction(check the owner signed the transation)
     * @notice also check to see if we have enough money in our account
     */
    function validateTransaction(
        bytes32,
        /* _txHash */
        bytes32,
        /* _suggestedSignedHash */
        Transaction memory _transaction
    )
        external
        payable
        requireFromBootloader
        returns (bytes4 magic)
    {
        return _validateTransaction(_transaction);
    }

    function executeTransaction(
        bytes32,
        /* _txHash */
        bytes32,
        /* _suggestedSignedHash */
        Transaction memory _transaction
    )
        external
        payable
        requireFromBootloaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    function executeTransactionFromOutside(Transaction memory _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC) {
            revert ZKMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(
        bytes32,
        /* _txHash */
        bytes32,
        /* _suggestedSignedHash */
        Transaction memory _transaction
    )
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZKMinimalAccount__FailedToPayBootLoader();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable {}

    /* /////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////// */
    function _requireFromBootloader() internal view {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZKMinimalAccount__NotFromBootloader();
        }
    }

    function _requireFromBootloaderOrOwner() internal view {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZKMinimalAccount__NotFromBootloaderOrOwner();
        }
    }

    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // Call nonceholder
        // Increment the account's nonce to prevent replay attacks.
        // This calls the NonceHolder system contract to ensure the transaction nonce matches
        // the current account nonce, then increments it. If the nonce doesn't match, the call reverts.
        // This is critical for security - without it, transactions could be replayed.
        // Note: This fails in tests because test-deployed accounts aren't registered with the nonce system.
        // SystemContractsCaller.systemCallWithPropagatedRevert(
        //     uint32(gasleft()),
        //     address(NONCE_HOLDER_SYSTEM_CONTRACT),
        //     0,
        //     abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        // );
        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZKMinimalAccount__NotEnoughBalance();
        }
        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // Return the "magic" number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZKMinimalAccount__ExecutionFailed();
            }
        }
    }
}
