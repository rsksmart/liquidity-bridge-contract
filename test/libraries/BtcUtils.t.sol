// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title BtcUtils Library Tests
/// @notice Tests for the BtcUtils library from @rsksmart/btc-transaction-solidity-helper
/// @dev These tests validate BTC transaction parsing with real transaction data
contract BtcUtilsTest is Test {
    using BtcUtils for bytes;

    /// @notice Test parsing P2PKH (Pay-to-PubKey-Hash) transactions
    /// @dev Replicates Hardhat test "parse raw btc transaction p2pkh script"
    function test_ParseRawBtcTransactionP2PKHScript() public pure {
        // First transaction: P2PKH with OP_RETURN containing quote hash
        bytes
            memory firstRawTx = hex"0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff0200879303000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a403938343934346435383039323135366335613139643936356239613735383530326536646263326439353337333135656266343839373336333134656233343700000000";

        BtcUtils.TxRawOutput[] memory firstTxOutputs = firstRawTx.getOutputs();

        // Parse null data script (OP_RETURN output)
        bytes memory firstNullScript = firstTxOutputs[1]
            .pkScript
            .parseNullDataScript();

        // Parse P2PKH destination address (testnet)
        bytes memory firstDestinationAddress = firstTxOutputs[0]
            .pkScript
            .parsePayToPubKeyHash(false);

        uint64 firstValue = firstTxOutputs[0].value;
        bytes32 firstHash = firstRawTx.hashBtcTx();

        // Verify first transaction parsing
        assertEq(
            firstNullScript.length,
            65,
            "Null script should be 65 bytes (1 size + 64 hash)"
        );
        assertEq(
            uint8(firstNullScript[0]),
            64,
            "First byte should be size (64)"
        );

        // Extract and verify the ASCII hash string
        bytes memory hashPart = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            hashPart[i] = firstNullScript[i + 1];
        }
        string memory hashString = string(hashPart);
        assertEq(
            hashString,
            "984944d58092156c5a19d965b9a758502e6dbc2d9537315ebf489736314eb347",
            "Hash string should match"
        );

        // Verify destination address (testnet P2PKH: mm2B8EUvZBZUi4BmBwN2M7RwgVBZ6BcVYU)
        // bs58check.decode("mm2B8EUvZBZUi4BmBwN2M7RwgVBZ6BcVYU") = 0x6f3c5f66fe733e0ad361805b3053f23212e5755c8d
        bytes
            memory expectedAddress = hex"6f3c5f66fe733e0ad361805b3053f23212e5755c8d";
        assertEq(
            firstDestinationAddress.length,
            expectedAddress.length,
            "Address length should match"
        );
        assertEq(
            keccak256(firstDestinationAddress),
            keccak256(expectedAddress),
            "First destination address should match"
        );

        assertEq(
            firstValue,
            60000000,
            "First value should be 60000000 satoshis"
        );
        assertEq(
            firstHash,
            0x03c4522ef958f724a7d2ffef04bd534d9eca74ffc0b28308797d2853bc323ba6,
            "First hash should match"
        );

        // Second transaction: Different P2PKH with different parameters
        bytes
            memory secondRawTx = hex"01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000";

        BtcUtils.TxRawOutput[] memory secondTxOutputs = secondRawTx
            .getOutputs();

        bytes memory secondNullScript = secondTxOutputs[1]
            .pkScript
            .parseNullDataScript();

        // Parse P2PKH destination address (mainnet)
        bytes memory secondDestinationAddress = secondTxOutputs[0]
            .pkScript
            .parsePayToPubKeyHash(true);

        uint64 secondValue = secondTxOutputs[0].value;
        bytes32 secondHash = secondRawTx.hashBtcTx();

        // Verify second transaction parsing
        assertEq(
            uint8(secondNullScript[0]),
            64,
            "Second null script first byte should be 64"
        );

        bytes memory secondHashPart = new bytes(64);
        for (uint i = 0; i < 64; i++) {
            secondHashPart[i] = secondNullScript[i + 1];
        }
        string memory secondHashString = string(secondHashPart);
        assertEq(
            secondHashString,
            "e94a89712629bbc9fccd1f0c04a278c0e1052eb7626f93e9a7f1067b406f0576",
            "Second hash string should match"
        );

        // Verify destination address (mainnet P2PKH: 16WDqBPwkA8Dvwi9UNPeXCDcpVar7XdD9y)
        // bs58check.decode("16WDqBPwkA8Dvwi9UNPeXCDcpVar7XdD9y") = 0x003c5f66fe733e0ad361805b3053f23212e5755c8d
        bytes
            memory expectedAddress2 = hex"003c5f66fe733e0ad361805b3053f23212e5755c8d";
        assertEq(
            keccak256(secondDestinationAddress),
            keccak256(expectedAddress2),
            "Second destination address should match"
        );

        assertEq(
            secondValue,
            70000000,
            "Second value should be 70000000 satoshis"
        );
        assertEq(
            secondHash,
            0xfd4251485dafe36aaa6766b38cf236b5925f23f12617daf286e0e92f73708aa3,
            "Second hash should match"
        );
    }

    /// @notice Test parsing various BTC transaction output types
    /// @dev Replicates Hardhat test "parse btc raw transaction outputs correctly"
    function test_ParseBtcRawTransactionOutputsCorrectly() public pure {
        // Test Case 1: SegWit transaction with P2WPKH outputs
        bytes
            memory tx1 = hex"01000000000101f73a1ea2f2cec2e9bfcac67b277cc9e4559ed41cfc5973c154b7bdcada92e3e90100000000ffffffff029ea8ef00000000001976a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88acb799f60300000000220020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d0400473044022051db70142aac24e8a13050cb0f61183704a7fe572c41a09caf5e7f56b7526f87022017d1a4b068a32af3dcea2d9a0e2f0d648c9f0f7fb01698d83091fd5b57f69ade01473044022028f29f5444ea4be2db3c6895e1414caa5cee9ab79faf1bf9bc12191f421de37102205af1df5158aa9c666f2d8d4d7c9da1ef96d28277f5d4b7c193e93e243a6641ae016952210375e00eb72e29da82b89367947f29ef34afb75e8654f6ea368e0acdfd92976b7c2103a1b26313f430c4b15bb1fdce663207659d8cac749a0e53d70eff01874496feff2103c96d495bfdd5ba4145e3e046fee45e84a8a48ad05bd8dbb395c011a32cf9f88053ae00000000";

        BtcUtils.TxRawOutput[] memory outputs1 = tx1.getOutputs();

        assertEq(outputs1.length, 2, "Should have 2 outputs");

        // First output: P2PKH
        assertEq(outputs1[0].value, 15706270, "Output 1 value");
        assertEq(
            outputs1[0].scriptSize,
            25,
            "Output 1 P2PKH script size should be 25"
        );
        assertEq(outputs1[0].totalSize, 34, "Output 1 total size");
        assertEq(
            keccak256(outputs1[0].pkScript),
            keccak256(hex"76a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88ac"),
            "Output 1 pkScript should match"
        );

        // Second output: P2WSH (witness v0 script hash)
        assertEq(outputs1[1].value, 66492855, "Output 2 value");
        assertEq(
            outputs1[1].scriptSize,
            34,
            "Output 2 P2WSH script size should be 34"
        );
        assertEq(outputs1[1].totalSize, 43, "Output 2 total size");
        assertEq(
            keccak256(outputs1[1].pkScript),
            keccak256(
                hex"0020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d"
            ),
            "Output 2 pkScript should match"
        );

        // Test Case 2: Coinbase transaction with OP_RETURN
        bytes
            memory tx2 = hex"010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff1a03583525e70ee95696543f47000000002f4e696365486173682fffffffff03c01c320000000000160014b0262460a83e78d991795007477d51d3998c70629581000000000000160014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b0000000000000000266a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f20120000000000000000000000000000000000000000000000000000000000000000000000000";

        BtcUtils.TxRawOutput[] memory outputs2 = tx2.getOutputs();

        assertEq(outputs2.length, 3, "Should have 3 outputs");

        // First output: P2WPKH
        assertEq(outputs2[0].value, 3284160, "Output 1 value");
        assertEq(outputs2[0].scriptSize, 22, "Output 1 script size");
        assertEq(outputs2[0].totalSize, 31, "Output 1 total size");
        assertEq(
            keccak256(outputs2[0].pkScript),
            keccak256(hex"0014b0262460a83e78d991795007477d51d3998c7062"),
            "Output 1 pkScript"
        );

        // Second output: P2WPKH
        assertEq(outputs2[1].value, 33173, "Output 2 value");
        assertEq(outputs2[1].scriptSize, 22, "Output 2 script size");
        assertEq(outputs2[1].totalSize, 31, "Output 2 total size");
        assertEq(
            keccak256(outputs2[1].pkScript),
            keccak256(hex"0014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b"),
            "Output 2 pkScript"
        );

        // Third output: OP_RETURN (null data)
        assertEq(outputs2[2].value, 0, "Output 3 value should be 0");
        assertEq(outputs2[2].scriptSize, 38, "Output 3 script size");
        assertEq(outputs2[2].totalSize, 47, "Output 3 total size");
        assertEq(
            keccak256(outputs2[2].pkScript),
            keccak256(
                hex"6a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f2"
            ),
            "Output 3 pkScript"
        );

        // Test Case 3: Another coinbase transaction
        bytes
            memory tx3 = hex"020000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff050261020101ffffffff02205fa012000000001976a91493fa9b864d39108a311918320e2a804de2e946f688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000";

        BtcUtils.TxRawOutput[] memory outputs3 = tx3.getOutputs();

        assertEq(outputs3.length, 2, "Should have 2 outputs");

        // First output: P2PKH
        assertEq(outputs3[0].value, 312500000, "Output 1 value");
        assertEq(outputs3[0].scriptSize, 25, "Output 1 script size");
        assertEq(outputs3[0].totalSize, 34, "Output 1 total size");
        assertEq(
            keccak256(outputs3[0].pkScript),
            keccak256(hex"76a91493fa9b864d39108a311918320e2a804de2e946f688ac"),
            "Output 1 pkScript"
        );

        // Second output: OP_RETURN
        assertEq(outputs3[1].value, 0, "Output 2 value should be 0");
        assertEq(outputs3[1].scriptSize, 38, "Output 2 script size");
        assertEq(outputs3[1].totalSize, 47, "Output 2 total size");
        assertEq(
            keccak256(outputs3[1].pkScript),
            keccak256(
                hex"6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9"
            ),
            "Output 2 pkScript"
        );
    }

    /// @notice Test parsing complex multi-input SegWit transaction
    /// @dev Tests a real transaction with 15 inputs and 2 outputs
    function test_ParseComplexSegWitTransaction() public pure {
        // Large SegWit transaction with 15 inputs
        bytes
            memory complexTx = hex"0100000000010fe0305a97189636fb57126d2f77a6364a5c6a809908270583438b3622dce6bc050000000000ffffffff6d487f63c4bd89b81388c20aeab8c775883ed56f11f509c248a7f00cdc64ae940000000000ffffffffa3d3d42b99de277265468acca3c081c811a9cc7522827aa95aeb42653c15fc330000000000ffffffffd7818dabb051c4db77da6d49670b0d3f983ba1d561343027870a7f3040af44fe0000000000ffffffff72daa44ef07b8d85e8ef8d9f055e07b5ebb8e1ba6a876e17b285946eb4ea9b9b0000000000ffffffff5264480a215536fd00d229baf1ab8c7c65ce10f37b783ca9700a828c3abc952c0000000000ffffffff712209f13eee0b9f3e6331040abcc09df750e4a287128922426d8d5c78ac9fc50000000000ffffffff21c5cf14014d28ec43a58f06f8e68c52c524a2b47b3be1c5800425e1f35f488d0000000000ffffffff2898464f9eb34f1d77fde2ed75dd9ae9c258f76030bb33be8e171d3e5f3b56390000000000ffffffffd27a5adff11cffc71d88face8f5adc2ce43ad648a997a5d54c06bcdec0e3eb5c0000000000ffffffff5217ca227f0e7f98984f19c59f895a3cfa7b05cb46ed844e2b0a26c9f5168d7a0000000000ffffffff8384e811f57e4515dd79ebfacf3a653200caf77f115bb6d4efe4bc534f0a39dd0000000000ffffffffd0448e1aae0ea56fab1c08dae1bdfe16c46f8ae8cec6042f6525bb7c1da0fa380000000000ffffffff5831c6df8395e3dc315af82c758c622156e2c40d677dececb717f4f20ded28a90000000000ffffffff56c2ffb0554631cff11e3e3fa90e6f35e76f420b29cde1faaa68c07cd0c6f8030100000000ffffffff02881300000000000016001463052ae51729396821a0cd91e0b1e9c61f53e168424e0800000000001600140d76db7b4f8f93a0b445bd782df2182a3e577604024730440220260695f8cf81168b46a24a07c380fd2568ee72f939309ed710e055f146d267db022044813ec9d65a57c8d4298b0bd9600664c3875bd2230b6a376a6fc70577a222bb012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100e0ed473c35a937d0b4d1a5e08f8e61248e80f5fe108c9b8b580792df8675a05d02202073dfd0d44d28780ee321c8a2d18da8157055d37d68793cbe8c53cc1c0a5321012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022034e28210fe7a14dde84cdb9ef4cf0a013bbc027deebcb56232ff2dabb25c12dc02202f4ff4df794ad3dbcfa4d498ec6d0c56b22c027004767851e3b8ffc5652ba529012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022030d5f4ffddf70a6086269ce982bff38c396831d0b5ef5205c3e557059903b2550220575bcf3b233c12b383bf2f16cd52e2fff2c488f0aa29ab3dec22b85b536b1c83012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100cc07265538f0ea4a8b999450549a965b0cc784371cac42cbcf8f49fbabf72b7c02207ef68377d7c6d3817d7c1a7a7936392b7043189ab1aed81eb0a7a3ad424bdcaf012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230248304502210085a8855abe9fd6680cb32911db66914cf970a30f01ecd17c7527fc369bb9f24002206da3457505a514a076954a2e5756fcc14c9e8bdc18301469dfe5b2b6daef723f012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d4e1963f5945dfae7dc73b0af1c65cf9156995a270164c2bcbc4a539130ac268022054464ea620730129ebaf95202f96f0b8be74ff660fcd748b7a107116e01730f3012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402207a5386c7b8bf3cf301fed36e18fe6527d35bc02007afda183e81fc39c1c8193702203207a6aa2223193a5c75ed8df0e046d390dbf862a3d0da1b2d0f300dfd42e8a7012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100c8db534b9ed20ce3a91b01b03e97a8f60853fbc16d19c6b587f92455542bc7c80220061d61d1c49a3f0dedecefaafc51526325bca972e99aaa367f2ebcab95d42395012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100f5287807debe8fc2eeee7adc5b7da8a212166a4580b8fdcf402c049a40b24fb7022006cb422492ba3b1ec257c64e74f3d439c00351f05bc05e88cab5cd9d4a7389b0012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402202edb544a679791424334e3c6a85613482ca3e3d16de0ca0d41c54babada8d4a2022025d0c937221161593bd9858bb3062216a4e55d191a07323104cfef1c7fcf5bc6012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402201a6cf02624884d4a1927cba36b2b9b02e1e6833a823204d8670d71646d2dd2c40220644176e293982f7a4acb25d79feda904a235f9e2664c823277457d33ccbaa6dc012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d49488c21322cd9a7c235ecddbd375656d98ba1ca06a5284c8c2ffb6bcbba83b02207dab29958d7c1b2466d5b5502b586d7f3d213b501689d42a313de91409179899012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402206ff3703495e0d872cbd1332d20ee39c14de6ed5a14808d80327ceedfda2329e102205da8497cb03776d5df8d67dc16617a6a3904f7abf85684a599ed6c60318aa3be012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2300000000";

        BtcUtils.TxRawOutput[] memory complexOutputs = complexTx.getOutputs();

        assertEq(complexOutputs.length, 2, "Should have 2 outputs");

        // First output: P2WPKH
        assertEq(complexOutputs[0].value, 5000, "Output 1 value");
        assertEq(complexOutputs[0].scriptSize, 22, "Output 1 script size");
        assertEq(complexOutputs[0].totalSize, 31, "Output 1 total size");
        assertEq(
            keccak256(complexOutputs[0].pkScript),
            keccak256(hex"001463052ae51729396821a0cd91e0b1e9c61f53e168"),
            "Output 1 pkScript"
        );

        // Second output: P2WPKH
        assertEq(complexOutputs[1].value, 544322, "Output 2 value");
        assertEq(complexOutputs[1].scriptSize, 22, "Output 2 script size");
        assertEq(complexOutputs[1].totalSize, 31, "Output 2 total size");
        assertEq(
            keccak256(complexOutputs[1].pkScript),
            keccak256(hex"00140d76db7b4f8f93a0b445bd782df2182a3e577604"),
            "Output 2 pkScript"
        );

        // Test Case 4: P2PKH transaction with OP_RETURN
        bytes
            memory tx4 = hex"01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000";

        BtcUtils.TxRawOutput[] memory outputs4 = tx4.getOutputs();

        assertEq(outputs4.length, 2, "Should have 2 outputs");

        // First output: P2PKH
        assertEq(outputs4[0].value, 70000000, "Output 1 value");
        assertEq(outputs4[0].scriptSize, 25, "Output 1 script size");
        assertEq(outputs4[0].totalSize, 34, "Output 1 total size");
        assertEq(
            keccak256(outputs4[0].pkScript),
            keccak256(hex"76a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac"),
            "Output 1 pkScript"
        );

        // Second output: OP_RETURN with 64-byte hash
        assertEq(outputs4[1].value, 0, "Output 2 value should be 0");
        assertEq(outputs4[1].scriptSize, 66, "Output 2 script size");
        assertEq(outputs4[1].totalSize, 75, "Output 2 total size");
        assertEq(
            keccak256(outputs4[1].pkScript),
            keccak256(
                hex"6a4065393461383937313236323962626339666363643166306330346132373863306531303532656237363236663933653961376631303637623430366630353736"
            ),
            "Output 2 pkScript"
        );
    }

    /// @notice Test parsing various BTC transaction hashes
    /// @dev Verifies that hashBtcTx produces correct double-SHA256 hashes
    function test_HashBtcTransactions() public pure {
        // Test with first transaction from P2PKH test
        bytes
            memory tx1 = hex"0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff0200879303000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a403938343934346435383039323135366335613139643936356239613735383530326536646263326439353337333135656266343839373336333134656233343700000000";

        bytes32 hash1 = tx1.hashBtcTx();
        assertEq(
            hash1,
            0x03c4522ef958f724a7d2ffef04bd534d9eca74ffc0b28308797d2853bc323ba6,
            "Hash 1 should match expected value"
        );

        // Test with second transaction
        bytes
            memory tx2 = hex"01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000";

        bytes32 hash2 = tx2.hashBtcTx();
        assertEq(
            hash2,
            0xfd4251485dafe36aaa6766b38cf236b5925f23f12617daf286e0e92f73708aa3,
            "Hash 2 should match expected value"
        );
    }
}
