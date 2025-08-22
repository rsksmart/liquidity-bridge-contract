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
          lbcAddress: "0xFD471836031dc5108809D173A067e8486B9047A3",
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
        hash: "0xa4eee92b46b53144d50fa986137a735f19011fcbcd5707509f5c15fb0c0470eb",
      },
      {
        quote: {
          lbcAddress: "0xFD471836031dc5108809D173A067e8486B9047A3",
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
        hash: "0x308f3581dfa77bd28efac42ff1fcbc2cac9c18ea9693623d9af997477acb6d52",
      },
      {
        quote: {
          lbcAddress: "0xFD471836031dc5108809D173A067e8486B9047A3",
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
        hash: "0x8dd5d591e6b01be794050be451ca1add56ff0f7689096c832afd7f1ddc3f1636",
      },
    ];
    for (const testCase of testCases) {
      await expect(
        contract.hashPegOutQuote(parsePegoutQuote(testCase.quote))
      ).to.eventually.eq(testCase.hash);
    }
  });
});
