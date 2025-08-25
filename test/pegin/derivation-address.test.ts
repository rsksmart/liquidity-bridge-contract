import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { deployCollateralManagement } from "../utils/fixtures";
import hre, { ethers, upgrades } from "hardhat";
import { PegInContract } from "../../typechain-types";
import { PEGIN_CONSTANTS, ZERO_ADDRESS } from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { ApiPeginQuote, parsePeginQuote } from "../../tasks/utils/quote";
import bs58 from "bs58";
import { expect } from "chai";

describe("PegInContract validatePegInDepositAddress function should", () => {
  const testCases: {
    quote: ApiPeginQuote;
    mainnetAddress: string;
    testnetAddress: string;
  }[] = [
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0x2B0d36FACD61B71CC05ab8F3D2355ec3631C0dd5",
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
      mainnetAddress: "3Lc4gDG8tKvH7pUAXrVdSqjgKNjw7rDuSM",
      testnetAddress: "2NCAGjxCAVnRdKc6iCz7W4niwXix6voH6hm",
    },
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0x2B0d36FACD61B71CC05ab8F3D2355ec3631C0dd5",
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
      mainnetAddress: "33LLHsHCHuSVSce3QV4t5VqxFYKan3fFW6",
      testnetAddress: "2MttYMcDDuMwqeQGb5cgkhSqDTtXkbc482q",
    },
    {
      quote: {
        fedBTCAddr: "3GQ87zLKyTygsRMZ1hfCHZSdBxujzKoCCU",
        lbcAddr: "0x2B0d36FACD61B71CC05ab8F3D2355ec3631C0dd5",
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
      mainnetAddress: "3Bus4sXKVv5eFRzsDRGKGoLqUg81pyrgkU",
      testnetAddress: "2N3U58cTM7NazTDdQtYtBtkL6h2LBdCRUtf",
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
