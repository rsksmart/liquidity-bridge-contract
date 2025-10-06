import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { ApiPeginQuote, parsePeginQuote } from "../../tasks/utils/quote";
import { deployPegInContractFixture } from "./fixtures";
import { expect } from "chai";
import { bech32 } from "bech32";
import { ethers } from "ethers";

describe("PegInContract hashPegInQuote function should", () => {
  const NATIVE_SEGWIT_MOCK_ADDRESS =
    "bc1quhhaa58r2xg3yu7ms85stpds0dmg896auw4nmh";
  const QUOTE_MOCK: ApiPeginQuote = {
    fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
    lbcAddr: "0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2",
    lpRSKAddr: "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
    btcRefundAddr: "1111111111111111111114oLvT2",
    rskRefundAddr: "0xaC31A4bEEdd7EC916b7a48A612230Cb85c1aaf56",
    lpBTCAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
    callFee: 100000000000000,
    penaltyFee: 10000000000000,
    contractAddr: "0xaC31A4bEEdd7EC916b7a48A612230Cb85c1aaf56",
    data: "0x",
    gasLimit: 21000,
    nonce: "3635227228603468300",
    value: "985215170000000000",
    agreementTimestamp: 1752739488,
    timeForDeposit: 5400,
    lpCallTime: 7200,
    confirmations: 3,
    callOnRegister: false,
    gasFee: 547377600000,
    productFeeAmount: 0,
  };

  it("revert if quote belongs to other contract", async () => {
    const { contract } = await loadFixture(deployPegInContractFixture);
    const quote = structuredClone(QUOTE_MOCK);
    quote.lbcAddr = "0xAA9cAf1e3967600578727F975F283446A3Da6612";
    await expect(contract.hashPegInQuote(parsePeginQuote(quote)))
      .to.be.revertedWithCustomError(contract, "IncorrectContract")
      .withArgs(QUOTE_MOCK.lbcAddr, quote.lbcAddr);
  });

  it("revert if destination address is the bridge address", async () => {
    const { contract, bridgeMock } = await loadFixture(
      deployPegInContractFixture
    );
    const bridgeAddress = await bridgeMock.getAddress();
    const quote = structuredClone(QUOTE_MOCK);
    quote.contractAddr = bridgeAddress;
    await expect(contract.hashPegInQuote(parsePeginQuote(quote)))
      .to.be.revertedWithCustomError(contract, "NoContract")
      .withArgs(quote.contractAddr);
  });

  it("revert if btcRefundAddress doesn't have the proper length", async () => {
    const { contract } = await loadFixture(deployPegInContractFixture);
    const quote = structuredClone(QUOTE_MOCK);
    const parsedQuote = parsePeginQuote(quote);
    parsedQuote.btcRefundAddress = new Uint8Array([
      ...bech32.decode(NATIVE_SEGWIT_MOCK_ADDRESS).words,
    ]);
    await expect(contract.hashPegInQuote(parsedQuote))
      .to.be.revertedWithCustomError(contract, "InvalidRefundAddress")
      .withArgs(parsedQuote.btcRefundAddress);
  });

  it("revert if liquidityProviderBtcAddress doesn't have the proper length", async () => {
    const { contract } = await loadFixture(deployPegInContractFixture);
    const quote = structuredClone(QUOTE_MOCK);
    const parsedQuote = parsePeginQuote(quote);
    parsedQuote.liquidityProviderBtcAddress = new Uint8Array([
      ...bech32.decode(NATIVE_SEGWIT_MOCK_ADDRESS).words,
    ]);
    await expect(contract.hashPegInQuote(parsedQuote))
      .to.be.revertedWithCustomError(contract, "InvalidRefundAddress")
      .withArgs(parsedQuote.liquidityProviderBtcAddress);
  });

  it("revert if quote total is under the bridge minimum", async () => {
    const { contract } = await loadFixture(deployPegInContractFixture);
    const quote = structuredClone(QUOTE_MOCK);
    const parsedQuote = parsePeginQuote(quote);
    parsedQuote.productFeeAmount = 99_999_999_999_999_999n;
    parsedQuote.gasFee = ethers.parseEther("0.1");
    parsedQuote.callFee = ethers.parseEther("0.1");
    parsedQuote.value = ethers.parseEther("0.2");
    await expect(contract.hashPegInQuote(parsedQuote))
      .to.be.revertedWithCustomError(contract, "AmountUnderMinimum")
      .withArgs(ethers.parseEther("0.5"));
  });

  it("revert if timestamp fields overflow when they are summed", async () => {
    const MAX_UINT_32 = 4_294_967_295n;
    const { contract } = await loadFixture(deployPegInContractFixture);
    const quote = structuredClone(QUOTE_MOCK);
    const parsedQuote = parsePeginQuote(quote);
    parsedQuote.agreementTimestamp = MAX_UINT_32 / 2n;
    parsedQuote.timeForDeposit = MAX_UINT_32 / 2n + 2n;
    await expect(contract.hashPegInQuote(parsedQuote))
      .to.be.revertedWithCustomError(contract, "Overflow")
      .withArgs(MAX_UINT_32);
  });

  it("hash pegin quote properly", async () => {
    const { contract } = await loadFixture(deployPegInContractFixture);
    const testCases: { quote: ApiPeginQuote; hash: string }[] = [
      {
        quote: QUOTE_MOCK,
        hash: "0x67e68a14a4a1ed6300970c7cd532cfd558206b3d7ac3fbc10e4cd67e5816e39d",
      },
      {
        quote: {
          fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
          lbcAddr: "0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2",
          lpRSKAddr: "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
          btcRefundAddr: "1111111111111111111114oLvT2",
          rskRefundAddr: "0x129D2280f9c35c0cAf3f172D487fD9A3f894fD26",
          lpBTCAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
          callFee: 1478412310000000,
          penaltyFee: 10000000000000,
          contractAddr: "0x129D2280f9c35c0cAf3f172D487fD9A3f894fD26",
          data: "0x",
          gasLimit: 21000,
          nonce: "6080686644105603000",
          value: "517700700000000000",
          agreementTimestamp: 1755356567,
          timeForDeposit: 7200,
          lpCallTime: 10800,
          confirmations: 2,
          callOnRegister: false,
          gasFee: 547377600000,
          productFeeAmount: 0,
        },
        hash: "0xf346bb77750943dbc7753f67ed01bd6c2be3ac77625157147687ccb4db72b3f7",
      },
      {
        quote: {
          fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
          lbcAddr: "0x2E2Ed0Cfd3AD2f1d34481277b3204d807Ca2F8c2",
          lpRSKAddr: "0x82a06ebdb97776a2da4041df8f2b2ea8d3257852",
          btcRefundAddr: "1111111111111111111114oLvT2",
          rskRefundAddr: "0xaC31A4bEEdd7EC916b7a48A612230Cb85c1aaf56",
          lpBTCAddr: "1D2xucTYkxCHvaaZuaKVJTfZQWr4PUjzAy",
          callFee: 2009314000000000,
          penaltyFee: 10000000000000,
          contractAddr: "0xaC31A4bEEdd7EC916b7a48A612230Cb85c1aaf56",
          data: "0x",
          gasLimit: 21000,
          nonce: "7756734892733337000",
          value: "578580000000000000",
          agreementTimestamp: 1755682139,
          timeForDeposit: 7200,
          lpCallTime: 10800,
          confirmations: 2,
          callOnRegister: false,
          gasFee: 547377600000,
          productFeeAmount: 0,
        },
        hash: "0x727ecad37c5569ebf89dcd67d76d0d60f2ea0dcf4efdf7ad6e061352ae0a85cc",
      },
    ];
    for (const testCase of testCases) {
      await expect(
        contract.hashPegInQuote(parsePeginQuote(testCase.quote))
      ).to.eventually.eq(testCase.hash);
    }
  });
});
