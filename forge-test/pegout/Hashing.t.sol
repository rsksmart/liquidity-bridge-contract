// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {Quotes} from "../../contracts/libraries/Quotes.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

contract HashingTest is PegOutTestBase {
    function setUp() public {
        deployPegOutContract();
    }

    // ============ hashPegOutQuote function tests ============

    function test_HashPegOutQuote_RevertsIfQuoteBelongsToOtherContract() public {
        address wrongContract = 0xAA9cAf1e3967600578727F975F283446A3Da6612;

        Quotes.PegOutQuote memory quote = Quotes.PegOutQuote({
            callFee: 300000000000000,
            penaltyFee: 10000000000000,
            value: 471000000000000000,
            productFeeAmount: 0,
            gasFee: 5990000000000,
            lbcAddress: wrongContract,
            lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            rskRefundAddress: 0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996,
            nonce: 5570584357569316000,
            agreementTimestamp: 1753461851,
            depositDateLimit: 1753469051,
            transferTime: 7200,
            depositConfirmations: 40,
            transferConfirmations: 2,
            expireBlock: 7822676,
            expireDate: 1753476251,
            depositAddress: new bytes(21),
            btcRefundAddress: new bytes(21),
            lpBtcAddress: new bytes(21)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.IncorrectContract.selector,
                address(pegOutContract),
                wrongContract
            )
        );
        pegOutContract.hashPegOutQuote(quote);
    }

    function test_HashPegOutQuote_HashesPegOutQuoteProperly() public view {
        // Note: Like PegIn hashing tests, we verify determinism rather than exact hashes
        // since the contract address is unpredictable in Foundry tests

        Quotes.PegOutQuote memory quote1 = createSpecificPegOutQuote1();
        quote1.lbcAddress = address(pegOutContract);

        // Hash the quote twice to verify it's deterministic
        bytes32 hash1a = pegOutContract.hashPegOutQuote(quote1);
        bytes32 hash1b = pegOutContract.hashPegOutQuote(quote1);
        assertEq(hash1a, hash1b, "Hash should be deterministic");

        // Verify different quotes produce different hashes
        Quotes.PegOutQuote memory quote2 = createSpecificPegOutQuote2();
        quote2.lbcAddress = address(pegOutContract);
        bytes32 hash2 = pegOutContract.hashPegOutQuote(quote2);

        assertTrue(hash1a != hash2, "Different quotes should produce different hashes");

        // Verify hash changes when quote value changes
        Quotes.PegOutQuote memory quote3 = createSpecificPegOutQuote1();
        quote3.lbcAddress = address(pegOutContract);
        quote3.value = 1 ether; // Different value
        bytes32 hash3 = pegOutContract.hashPegOutQuote(quote3);

        assertTrue(hash1a != hash3, "Changing quote value should change hash");
    }

    // ============ Helper Functions ============

    function createSpecificPegOutQuote1() internal pure returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegOutQuote({
            callFee: 300000000000000,
            penaltyFee: 10000000000000,
            value: 471000000000000000,
            productFeeAmount: 0,
            gasFee: 5990000000000,
            lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
            lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            rskRefundAddress: 0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996,
            nonce: 5570584357569316000,
            agreementTimestamp: 1753461851,
            depositDateLimit: 1753469051,
            transferTime: 7200,
            depositConfirmations: 40,
            transferConfirmations: 2,
            expireBlock: 7822676,
            expireDate: 1753476251,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }

    function createSpecificPegOutQuote2() internal pure returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegOutQuote({
            callFee: 300000000000000,
            penaltyFee: 10000000000000,
            value: 27108379819732510,
            productFeeAmount: 1,
            gasFee: 11330000000000,
            lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
            lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            rskRefundAddress: 0x02E221A95224F090e492066Bc1B7a35B5Fd94542,
            nonce: 3434440345862007300,
            agreementTimestamp: 1753727248,
            depositDateLimit: 1753734448,
            transferTime: 7200,
            depositConfirmations: 40,
            transferConfirmations: 2,
            expireBlock: 7833647,
            expireDate: 1753741648,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }

    function createSpecificPegOutQuote3() internal pure returns (Quotes.PegOutQuote memory) {
        bytes memory testBtcAddress = new bytes(21);

        return Quotes.PegOutQuote({
            callFee: 300000000000000,
            penaltyFee: 10000000000000,
            value: 1045000000000000000,
            productFeeAmount: 3,
            gasFee: 3140000000000,
            lbcAddress: 0x4C2F7092C2aE51D986bEFEe378e50BD4dB99C901,
            lpRskAddress: 0x82a06eBDB97776a2da4041dF8f2b2ea8D3257852,
            rskRefundAddress: 0x077B8Cd0e024e79eEFc8Ce1Fddc005DbE88A94c7,
            nonce: 877548865611330300,
            agreementTimestamp: 1753945401,
            depositDateLimit: 1753952601,
            transferTime: 7200,
            depositConfirmations: 60,
            transferConfirmations: 3,
            expireBlock: 7842574,
            expireDate: 1753959801,
            depositAddress: testBtcAddress,
            btcRefundAddress: testBtcAddress,
            lpBtcAddress: testBtcAddress
        });
    }
}
