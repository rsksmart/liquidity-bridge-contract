// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

library FlyoverModule {
    bytes32 public constant MODULE_ROLE = keccak256("MODULE_ROLE");
    bytes32 public constant INTERNAL_MODULE_ROLE = keccak256("INTERNAL_MODULE_ROLE");

    int16 constant public BRIDGE_REFUNDED_USER_ERROR_CODE = -100;
    int16 constant public BRIDGE_REFUNDED_LP_ERROR_CODE = -200;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_NOT_CONTRACT_ERROR_CODE = -300;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_INVALID_SENDER_ERROR_CODE = -301;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_ALREADY_PROCESSED_ERROR_CODE = -302;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_VALIDATIONS_ERROR = -303;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_VALUE_ZERO_ERROR = -304;
    int16 constant public BRIDGE_UNPROCESSABLE_TX_UTXO_AMOUNT_SENT_BELOW_MINIMUM_ERROR = -305;
    int16 constant public BRIDGE_GENERIC_ERROR = -900;
}