import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ApiPegoutQuote, parsePegoutQuote } from "../../tasks/utils/quote";
import { deployPegOutContractFixture } from "./fixtures";
import { expect } from "chai";

describe("PegOutContract hashPegOutQuote function should", () => {
  it("revert if quote belongs to other contract", async () => {
    const { contract } = await loadFixture(deployPegOutContractFixture);
    const quote: ApiPegoutQuote = {
      lbcAddress: "0xAA9cAf1e3967600578727F975F283446A3Da6612",
      liquidityProviderRskAddress: "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
      btcRefundAddress: "bc1qlc98wwylr3g6kknh86a8gkdqmhf6vly527h2yv",
      rskRefundAddress: "0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996",
      lpBtcAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
      callFee: 300000000000000,
      penaltyFee: 10000000000000,
      nonce: "5570584357569316000",
      depositAddr: "bc1qlc98wwylr3g6kknh86a8gkdqmhf6vly527h2yv",
      value: "471000000000000000",
      agreementTimestamp: 1753461851,
      depositDateLimit: 1753469051,
      depositConfirmations: 40,
      transferConfirmations: 2,
      transferTime: 7200,
      expireDate: 1753476251,
      expireBlocks: 7822676,
      gasFee: 5990000000000,
      productFeeAmount: 0,
    };
    await expect(contract.hashPegOutQuote(parsePegoutQuote(quote)))
      .to.be.revertedWithCustomError(contract, "IncorrectContract")
      .withArgs(await contract.getAddress(), quote.lbcAddress);
  });
  it("hash pegout quote properly", async () => {
    const { contract } = await loadFixture(deployPegOutContractFixture);
    const testCases: { quote: ApiPegoutQuote; hash: string }[] = [
      {
        quote: {
          lbcAddress: "0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8",
          liquidityProviderRskAddress:
            "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
          btcRefundAddress: "bc1qlc98wwylr3g6kknh86a8gkdqmhf6vly527h2yv",
          rskRefundAddress: "0xF52e06Df2E1cbD73fb686442319cbe5Ce495B996",
          lpBtcAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
          callFee: 300000000000000,
          penaltyFee: 10000000000000,
          nonce: "5570584357569316000",
          depositAddr: "bc1qlc98wwylr3g6kknh86a8gkdqmhf6vly527h2yv",
          value: "471000000000000000",
          agreementTimestamp: 1753461851,
          depositDateLimit: 1753469051,
          depositConfirmations: 40,
          transferConfirmations: 2,
          transferTime: 7200,
          expireDate: 1753476251,
          expireBlocks: 7822676,
          gasFee: 5990000000000,
          productFeeAmount: 0,
        },
        hash: "0x185e5ae2ad8f2210d430c5cdc3a4d3a0ea8c086ffbf6195eda0abc912ea30b27",
      },
      {
        quote: {
          lbcAddress: "0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8",
          liquidityProviderRskAddress:
            "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
          btcRefundAddress: "1KMCKD5ySjvugtyBgiADNhvDJ42QRD9Erp",
          rskRefundAddress: "0x02E221A95224F090e492066Bc1B7a35B5Fd94542",
          lpBtcAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
          callFee: 300000000000000,
          penaltyFee: 10000000000000,
          nonce: "3434440345862007300",
          depositAddr: "1KMCKD5ySjvugtyBgiADNhvDJ42QRD9Erp",
          value: "27108379819732510",
          agreementTimestamp: 1753727248,
          depositDateLimit: 1753734448,
          depositConfirmations: 40,
          transferConfirmations: 2,
          transferTime: 7200,
          expireDate: 1753741648,
          expireBlocks: 7833647,
          gasFee: 11330000000000,
          productFeeAmount: 1,
        },
        hash: "0x3ea79cf1c080f9e3c48b4e4db31a57ecf0b09dfe78f605f786d3ef10f3c06aec",
      },
      {
        quote: {
          lbcAddress: "0xf4B146FbA71F41E0592668ffbF264F1D186b2Ca8",
          liquidityProviderRskAddress:
            "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
          btcRefundAddress:
            "bc1p9yzdqu4de2kjq9j7gsxegzmfze678dvn9qvzjexj87d26as0yacsm7u8ar",
          rskRefundAddress: "0x077B8Cd0e024e79eEFc8Ce1Fddc005DbE88A94c7",
          lpBtcAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
          callFee: 300000000000000,
          penaltyFee: 10000000000000,
          nonce: "877548865611330300",
          depositAddr:
            "bc1p9yzdqu4de2kjq9j7gsxegzmfze678dvn9qvzjexj87d26as0yacsm7u8ar",
          value: "1045000000000000000",
          agreementTimestamp: 1753945401,
          depositDateLimit: 1753952601,
          depositConfirmations: 60,
          transferConfirmations: 3,
          transferTime: 7200,
          expireDate: 1753959801,
          expireBlocks: 7842574,
          gasFee: 3140000000000,
          productFeeAmount: 3,
        },
        hash: "0x4710b80cdaba6541a6b3a4775ab86ff6fc3bbe317f4a35d9b69e8eec114a0fab",
      },
    ];
    for (const testCase of testCases) {
      await expect(
        contract.hashPegOutQuote(parsePegoutQuote(testCase.quote))
      ).to.eventually.eq(testCase.hash);
    }
  });
});
