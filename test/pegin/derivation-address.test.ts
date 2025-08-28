import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import hre, { ethers, upgrades } from "hardhat";
import { PegInContract } from "../../typechain-types";
import { PEGIN_CONSTANTS, ZERO_ADDRESS } from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { ApiPeginQuote, parsePeginQuote } from "../../tasks/utils/quote";
import bs58 from "bs58";
import { expect } from "chai";
import { deployCollateralManagement } from "../collateral/fixtures";

describe("PegInContract validatePegInDepositAddress function should", () => {
  const testCases: {
    quote: ApiPeginQuote;
    mainnetAddress: string;
    testnetAddress: string;
  }[] = [
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0xC9a43158891282A2B1475592D5719c001986Aaec",
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
      },
      mainnetAddress: "3NL4vLByNyjHEZrZpjgW9Wtk2TcLsJSZAn",
      testnetAddress: "2NDtGz57zzSEdSMV7VsJNmTt1EopWdjF8ty",
    },
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0xC9a43158891282A2B1475592D5719c001986Aaec",
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
      mainnetAddress: "3NYC8YUBenys3rF3XLGd3riBzVDcsGvnA9",
      testnetAddress: "2NE6QCHQDGFVDFdsbCTtVfohTCqRngyKtz7",
    },
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0xC9a43158891282A2B1475592D5719c001986Aaec",
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
      mainnetAddress: "34W24FRzEwbW1yiqjs1QgtaXp2rbdboypb",
      testnetAddress: "2Mv4E7zN1rQ6rDmMPQzdHJqZo2P4mRsc6dU",
    },
  ];

  it("validate addresses properly in mainnet", async () => {
    const deployResult = await loadFixture(deployCollateralManagement);
    const collateralManagement = deployResult.collateralManagement;
    const collateralManagementAddress = await collateralManagement.getAddress();
    const bridgeMock = await ethers.deployContract("BridgeMock");

    const initializationParams: Parameters<PegInContract["initialize"]> = [
      deployResult.owner.address,
      await bridgeMock.getAddress(),
      PEGIN_CONSTANTS.TEST_DUST_THRESHOLD,
      PEGIN_CONSTANTS.TEST_MIN_PEGIN,
      collateralManagementAddress,
      true,
      0,
      ZERO_ADDRESS,
    ];

    const libraries = await deployLibraries(
      hre.network.name,
      "Quotes",
      "BtcUtils",
      "SignatureValidator"
    );
    const PegInContract = await ethers.getContractFactory("PegInContract", {
      libraries: {
        Quotes: libraries.Quotes.address,
        BtcUtils: libraries.BtcUtils.address,
        SignatureValidator: libraries.SignatureValidator.address,
      },
    });

    const contract = await upgrades.deployProxy(
      PegInContract,
      initializationParams,
      {
        unsafeAllow: ["external-library-linking"],
      }
    );

    for (const test of testCases) {
      const decoded = bs58.decode(test.mainnetAddress);
      await expect(
        contract.validatePegInDepositAddress(
          parsePeginQuote(test.quote),
          decoded
        )
      ).to.eventually.eq(true);
    }
  });

  it("validate addresses properly in testnet", async () => {
    const deployResult = await loadFixture(deployCollateralManagement);
    const collateralManagement = deployResult.collateralManagement;
    const collateralManagementAddress = await collateralManagement.getAddress();
    const bridgeMock = await ethers.deployContract("BridgeMock");

    const initializationParams: Parameters<PegInContract["initialize"]> = [
      deployResult.owner.address,
      await bridgeMock.getAddress(),
      PEGIN_CONSTANTS.TEST_DUST_THRESHOLD,
      PEGIN_CONSTANTS.TEST_MIN_PEGIN,
      collateralManagementAddress,
      false,
      0,
      ZERO_ADDRESS,
    ];

    const libraries = await deployLibraries(
      hre.network.name,
      "Quotes",
      "BtcUtils",
      "SignatureValidator"
    );
    const PegInContract = await ethers.getContractFactory("PegInContract", {
      libraries: {
        Quotes: libraries.Quotes.address,
        BtcUtils: libraries.BtcUtils.address,
        SignatureValidator: libraries.SignatureValidator.address,
      },
    });

    const contract = await upgrades.deployProxy(
      PegInContract,
      initializationParams,
      {
        unsafeAllow: ["external-library-linking"],
      }
    );

    for (const test of testCases) {
      const decoded = bs58.decode(test.testnetAddress);
      await expect(
        contract.validatePegInDepositAddress(
          parsePeginQuote(test.quote),
          decoded
        )
      ).to.eventually.eq(true);
    }
  });
});
