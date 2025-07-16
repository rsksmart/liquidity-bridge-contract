import hre, { ethers } from "hardhat";
import {
  anyHex,
  anyNumber,
  LP_COLLATERAL,
  ZERO_ADDRESS,
} from "./utils/constants";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployContract } from "../scripts/deployment-utils/utils";
import { deployLbcWithProvidersFixture } from "./utils/fixtures";
import {
  getBtcPaymentBlockHeaders,
  getTestPeginQuote,
  totalValue,
} from "./utils/quotes";
import { getBytes } from "ethers";
import {
  createBalanceDifferenceAssertion,
  createCollateralUpdateAssertion,
} from "./utils/asserts";
import * as bs58check from "bs58check";
import bs58 from "bs58";
import { QuotesV2 } from "../typechain-types";
import { getTestMerkleProof } from "./utils/btc";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";

describe("LiquidityBridgeContractV2 pegin process should", () => {
  it("call contract for user", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock } = fixtureResult;
    let lbc = fixtureResult.lbc;

    const provider = liquidityProviders[0];
    const deploymentInfo = await deployContract("Mock", hre.network.name);
    const mockContract = await ethers.getContractAt(
      "Mock",
      deploymentInfo.address
    );
    const refundAddress = await ethers
      .getSigners()
      .then((accounts) => accounts[0].address);
    const destinationAddress = await mockContract.getAddress();
    const data = mockContract.interface.encodeFunctionData("set", [12]);
    const quote = getTestPeginQuote({
      destinationAddress: destinationAddress,
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      refundAddress: refundAddress,
      value: ethers.parseEther("20"),
      data: data,
    });

    const btcRawTransaction = "0x1010";
    const partialMerkleTree = "0x0202";
    const height = 10;
    const peginAmount = totalValue(quote);
    const lpBalanceAfterCfuAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect LP balance after callForUser",
    });
    const lpBalanceAfterRegisterAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
        message: "Incorrect LP balance after registerPegin",
      });
    const lbcBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
      message: "Incorrect LBC balance after pegin",
    });

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });

    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await mockContract.set(0);

    const lpCollateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });

    lbc = lbc.connect(provider.signer);
    const cfuTx = await lbc.callForUser(quote, { value: quote.value });
    await cfuTx.wait();

    await lpBalanceAfterCfuAssertion();

    const registerPeginResult = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );

    await expect(cfuTx)
      .to.emit(lbc, "CallForUser")
      .withArgs(
        quote.liquidityProviderRskAddress,
        quote.contractAddress,
        quote.gasLimit,
        quote.value,
        quote.data,
        true,
        quoteHash
      );
    await expect(registerTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);

    expect(registerPeginResult).to.be.eq(peginAmount);
    await lpBalanceAfterRegisterAssertion();
    await lbcBalanceAssertion();
    await lpCollateralAssertion();
    await expect(mockContract.check()).eventually.to.eq(12);
  });
  it("fail on contract call due to invalid lbc address", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const provider = fixtureResult.liquidityProviders[1];
    let lbc = fixtureResult.lbc;
    lbc = lbc.connect(provider.signer);

    const accounts = fixtureResult.accounts;
    const destinationAddress = accounts[0].address;
    const refundAddress = accounts[1].address;
    const notLbcAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: notLbcAddress,
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: refundAddress,
      value: ethers.parseEther("0.5"),
    });

    await expect(lbc.callForUser(quote)).to.be.revertedWith("LBC019");
    await expect(
      lbc.callForUser(quote, { value: quote.value })
    ).to.be.revertedWith("LBC051");
    const registerPeginTx = lbc.registerPegIn(
      quote,
      anyHex,
      anyHex,
      anyHex,
      anyNumber
    );
    await expect(registerPeginTx).to.be.revertedWith("LBC051");
  });
  it("fail on contract call due to invalid contract address", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const provider = liquidityProviders[0];
    lbc = lbc.connect(provider.signer);

    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: await bridgeMock.getAddress(),
      refundAddress: accounts[0].address,
      value: ethers.parseEther("0.5"),
    });

    await expect(lbc.hashQuote(quote)).to.be.revertedWith("LBC052");
    await expect(
      lbc.callForUser(quote, { value: quote.value })
    ).to.be.revertedWith("LBC052");
    const registerPeginTx = lbc.registerPegIn(
      quote,
      anyHex,
      anyHex,
      anyHex,
      anyNumber
    );
    await expect(registerPeginTx).to.be.revertedWith("LBC052");
  });

  it("fail on contract call due to invalid user btc refund address", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    let lbc = fixtureResult.lbc;
    const provider = fixtureResult.liquidityProviders[0];
    lbc = lbc.connect(provider.signer);
    const accounts = fixtureResult.accounts;
    const destinationAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: destinationAddress,
      value: ethers.parseEther("0.5"),
    });
    const invalidAddresses = [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ];

    for (const address of invalidAddresses) {
      quote.btcRefundAddress = address;
      await expect(lbc.hashQuote(quote)).to.be.revertedWith("LBC053");
      await expect(
        lbc.callForUser(quote, { value: quote.value })
      ).to.be.revertedWith("LBC053");
      const registerPeginTx = lbc.registerPegIn(
        quote,
        anyHex,
        anyHex,
        anyHex,
        anyNumber
      );
      await expect(registerPeginTx).to.be.revertedWith("LBC053");
    }
  });

  it("fail on contract call due to invalid lp btc address", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    let lbc = fixtureResult.lbc;
    const provider = fixtureResult.liquidityProviders[1];
    lbc = lbc.connect(provider.signer);
    const accounts = fixtureResult.accounts;
    const destinationAddress = accounts[0].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: destinationAddress,
      value: ethers.parseEther("0.5"),
    });
    const invalidAddresses = [
      "0x0000000000000000000000000000000000000012" /* 20 bytes */,
      "0x00000000000000000000000000000000000000000012" /* 22 bytes */,
    ];

    for (const address of invalidAddresses) {
      quote.liquidityProviderBtcAddress = address;
      await expect(lbc.hashQuote(quote)).to.be.revertedWith("LBC054");
      await expect(
        lbc.callForUser(quote, { value: quote.value })
      ).to.be.revertedWith("LBC054");
      const registerPeginTx = lbc.registerPegIn(
        quote,
        anyHex,
        anyHex,
        anyHex,
        anyNumber
      );
      await expect(registerPeginTx).to.be.revertedWith("LBC054");
    }
  });

  it("fail on contract call due to quote value+fee being below min peg-in", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    let lbc = fixtureResult.lbc;
    const provider = fixtureResult.liquidityProviders[1];
    lbc = lbc.connect(provider.signer);
    const accounts = fixtureResult.accounts;
    const destinationAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: destinationAddress,
      value: ethers.parseEther("0.1"),
    });

    await expect(lbc.hashQuote(quote)).to.be.revertedWith("LBC055");
    await expect(
      lbc.callForUser(quote, { value: quote.value })
    ).to.be.revertedWith("LBC055");
    const registerPeginTx = lbc.registerPegIn(
      quote,
      anyHex,
      anyHex,
      anyHex,
      anyNumber
    );
    await expect(registerPeginTx).to.be.revertedWith("LBC055");
  });

  it("should transfer value for user", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const daoFee = 100000000000n;
    const provider = liquidityProviders[1];
    lbc = lbc.connect(provider.signer);

    const rskRefundAddress = accounts[2].address;
    const destinationAddress = accounts[1].address;
    const lbcAddress = await lbc.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress: lbcAddress,
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: rskRefundAddress,
      value: ethers.parseEther("10"),
    });
    quote.productFeeAmount = daoFee;
    const peginAmount = totalValue(quote);

    const userBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: destinationAddress,
      expectedDiff: quote.value,
      message: "Incorrect user balance after pegin",
    });

    const feeCollectorBalanceAssertion = await createBalanceDifferenceAssertion(
      {
        source: ethers.provider,
        address: ZERO_ADDRESS,
        expectedDiff: daoFee,
        message: "Incorrect DAO fee collector balance after pegin",
      }
    );

    const lpBalanceAfterCfuAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect LP balance after call for user",
    });

    const lpBalanceAfterRegisterAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
        message: "Incorrect LP balance after register pegin",
      });

    const lbcBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: lbcAddress,
      expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
      message: "Incorrect LBC balance after pegin",
    });

    const lpCollateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const height = 10;

    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const cfuTx = await lbc.callForUser(quote, { value: quote.value });
    await cfuTx.wait();

    await lpBalanceAfterCfuAssertion();

    const registerPeginResult = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      anyHex,
      anyHex,
      height
    );

    const registerPeginTx = await lbc.registerPegIn(
      quote,
      signature,
      anyHex,
      anyHex,
      height
    );

    await expect(registerPeginTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);

    await expect(cfuTx)
      .to.emit(lbc, "CallForUser")
      .withArgs(
        quote.liquidityProviderRskAddress,
        quote.contractAddress,
        quote.gasLimit,
        quote.value,
        quote.data,
        true,
        quoteHash
      );

    await expect(registerPeginTx)
      .to.emit(lbc, "DaoFeeSent")
      .withArgs(quoteHash, daoFee);

    await userBalanceAssertion();
    await lbcBalanceAssertion();
    await lpCollateralAssertion();
    await lpBalanceAfterRegisterAssertion();
    await feeCollectorBalanceAssertion();
    expect(registerPeginResult).to.be.eq(peginAmount);
  });

  it("not generate transaction to DAO when product fee is 0 in registerPegIn", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const provider = liquidityProviders[1];
    lbc = lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const lbcAddress = await lbc.getAddress();
    const quote = getTestPeginQuote({
      lbcAddress: lbcAddress,
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: destinationAddress,
      value: ethers.parseEther("10"),
    });
    const peginAmount = totalValue(quote);

    const feeCollectorBalanceAssertion = await createBalanceDifferenceAssertion(
      {
        source: ethers.provider,
        address: ZERO_ADDRESS,
        expectedDiff: 0,
        message: "Incorrect DAO fee collector balance after pegin",
      }
    );

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const height = 10;

    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const cfuTx = await lbc.callForUser(quote, { value: quote.value });
    await cfuTx.wait();

    const registerPeginTx = await lbc.registerPegIn(
      quote,
      signature,
      anyHex,
      anyHex,
      height
    );

    await expect(registerPeginTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);

    await expect(cfuTx)
      .to.emit(lbc, "CallForUser")
      .withArgs(
        quote.liquidityProviderRskAddress,
        quote.contractAddress,
        quote.gasLimit,
        quote.value,
        quote.data,
        true,
        quoteHash
      );

    expect(quote.productFeeAmount).to.be.eq(0);
    await expect(registerPeginTx).not.to.emit(lbc, "DaoFeeSent");
    await feeCollectorBalanceAssertion();
  });

  it("verify depositAddress for given quote", async () => {
    const { lbc } = await loadFixture(deployLbcWithProvidersFixture);
    const lbcAddress = await lbc.getAddress();
    const tests = [
      {
        quote: {
          fedBtcAddress: bs58check
            .decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p")
            .slice(1),
          lbcAddress: lbcAddress,
          liquidityProviderRskAddress:
            "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress: bs58check.decode(
            "mxqk28jvEtvjxRN8k7W9hFEJfWz5VcUgHW"
          ),
          rskRefundAddress: "0xa2193A393aa0c94A4d52893496F02B56C61c36A1",
          liquidityProviderBtcAddress: bs58check.decode(
            "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
          ),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0xa2193A393aa0c94A4d52893496F02B56C61c36A1",
          data: "0x",
          gasLimit: 46000,
          nonce: BigInt("3426962016206607167"),
          value: BigInt("600000000000000000"),
          agreementTimestamp: 1691772110,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("6000000000000000"),
          gasFee: BigInt("3000000000000000"),
        },
        address: "2NAXHKYRnTme4oDCk9mSPfdf4ga2tZ1xM5B",
      },
      {
        quote: {
          fedBtcAddress: bs58check
            .decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p")
            .slice(1),
          lbcAddress: lbcAddress,
          liquidityProviderRskAddress:
            "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress: bs58check.decode(
            "mi5vEG69RGhi3RKsn7bWco5xnafZvsXvrF"
          ),
          rskRefundAddress: "0x69b3886457c0e0654d9829d29a6156f49236235c",
          liquidityProviderBtcAddress: bs58check.decode(
            "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
          ),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0x7221249458b5e2055b33069a27836985a3822c99",
          data: "0x",
          gasLimit: 46000,
          nonce: BigInt("7363369648470809209"),
          value: BigInt("700000000000000000"),
          agreementTimestamp: 1691873604,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("7000000000000000"),
          gasFee: BigInt("4000000000000000"),
        },
        address: "2NCDJzPze5eosHN5Tx4pf5GF2zXtaKDUHzX",
      },
      {
        quote: {
          fedBtcAddress: bs58check
            .decode("2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p")
            .slice(1),
          lbcAddress: lbcAddress,
          liquidityProviderRskAddress:
            "0x9D93929A9099be4355fC2389FbF253982F9dF47c",
          btcRefundAddress: bs58check.decode(
            "mjSE41mAMwqdYsXiibUgyWe4oESoCygf96"
          ),
          rskRefundAddress: "0xc67319ce23965591947a93884356252477330456",
          liquidityProviderBtcAddress: bs58check.decode(
            "mnYcQxCZBbmLzNfE9BhV7E8E2u7amdz5y6"
          ),
          callFee: BigInt("1000000000000000"),
          penaltyFee: 1000000,
          contractAddress: "0x48c8396629c550203e183350c9074a2b42e83d1a",
          data: "0x",
          gasLimit: 46000,
          nonce: BigInt("8681289575209299775"),
          value: BigInt("800000000000000000"),
          agreementTimestamp: 1691874253,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 10,
          callOnRegister: false,
          productFeeAmount: BigInt("8000000000000000"),
          gasFee: BigInt("5000000000000000"),
        },
        address: "2N7rxjtHjbxr8W3U3HVncyHJhEhBQ3tBa9w",
      },
    ];

    for (const test of tests) {
      const decoded = bs58.decode(test.address);
      await expect(
        lbc.validatePeginDepositAddress(test.quote, decoded)
      ).to.eventually.eq(true);
    }
  });

  it("throw error in hashQuote if summing quote agreementTimestamp and timeForDeposit cause overflow", async () => {
    const { lbc, accounts, liquidityProviders } = await loadFixture(
      deployLbcWithProvidersFixture
    );
    const user = accounts[0];
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: liquidityProviders[0].signer,
      destinationAddress: user.address,
      refundAddress: user.address,
      value: ethers.parseEther("10"),
    });
    quote.agreementTimestamp = 4294967294;
    quote.timeForDeposit = 4294967294;
    await expect(lbc.hashQuote(quote)).to.be.revertedWith("LBC071");
  });

  it("refund pegin with wrong amount without penalizing the LP (real cases)", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const lp = fixtureResult.liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(lp.signer);
    const bridgeMock = fixtureResult.bridgeMock;
    interface TestCase {
      quote: QuotesV2.PeginQuoteStruct;
      quoteHash: string;
      signature: string;
      btcRawTx: string;
      pmt: string;
      height: number;
      refundAmount: string;
    }
    const cases: TestCase[] = [
      {
        quote: {
          fedBtcAddress: bs58check
            .decode("3LxPz39femVBL278mTiBvgzBNMVFqXssoH")
            .slice(1),
          lbcAddress: "0xAA9cAf1e3967600578727F975F283446A3Da6612",
          liquidityProviderRskAddress:
            "0x4202bac9919c3412fc7c8be4e678e26279386603",
          btcRefundAddress: bs58check.decode(
            "1K5X7aTGfZGksihgNdDschakaxp8ZhT1F3"
          ),
          rskRefundAddress: "0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10",
          liquidityProviderBtcAddress: bs58check.decode(
            "17kksixYkbHeLy9okV16kr4eAxVhFkRhP"
          ),
          callFee: "100000000000000",
          penaltyFee: "10000000000000",
          contractAddress: "0x1bf357F3CcCe62a5Dd1035c79070BdA219C53B10",
          data: "0x",
          gasLimit: 21000,
          nonce: "907664817259568253",
          value: "5200000000000000",
          agreementTimestamp: 1727278204,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 2,
          callOnRegister: false,
          productFeeAmount: 0,
          gasFee: "1354759560000",
        },
        quoteHash:
          "b21ead431a1c3efd1759b62a56c253d740d1bf3c3673cd060aed64906a82c1c3",
        signature:
          "c72e3e5bb9cf6bf3db568df18d2dba80896490cda7371c4643cad116d54d46c50a368d4cfa0b963468c5db15b773f4d1ea1ab69565a3f903ac3ab363204ba3bc1c",
        btcRawTx:
          "020000000212bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff046d8f4e5fa8d6cc5fa23c50640249461b646e8a4722c9cfbfbff00c049d559f0000000017160014fe7b123124c87300e8ba30f0e2eafdd8e1f2b337ffffffff02d71608000000000017a9149fa51efd2954990e4974e7b13468fb8be54512d8872d2507000000000017a914b979999438ade0fdd2cf303fca55ea29aec2392b8700000000",
        pmt: "800c00000d3eb13be27a4110f06ca8e4b4b00103e10ac6ba5f9123934764ac9555e2ec3c7b88a5464adca8b40a548741a8262dc2ab228f89cbd51bbf57f3f5d67130820ae3f9b7625821c2d9718d6611de40edfa1eb42181f180aab3891730584921a125dddba628c1d3f5fca59e0b68494aae191ab14db30b79e07962da298a52bcf077905661f80bd5731e0c80524ba2f7dcad0bd05a0d470bccdb5c5889c9c71ac7c5bca7f6cebd492154af69f2b98bcf7995444c765a18445a5ef212eb5f8ead5a441a45536e4075022614df043d03b2449113a00f32cff333024d3a1d66d84d4a31c012bebc8ba671aa9af2e3984af89366b5594ed115dbbaef64a41e8650cd4a53ea34b89cb98fac941bdd048d4a8f371d7b9f132ad19f1542556c89b4e8701022de51f6d49aa8f7e7d01591de9bdef65351e8590f111ea9be5550f66a3d4a734758e26b8edf2bfe9c4375929fea7b7197a24589648f8e7b934a6caa2d9c7583e64a28db12de953b0abddbdc3edb28b845eaca02f56dd52aa04e3131dc539c0f646f35751d1ec529231acd5cb079b4a2b678ecd3fc07636be878e6336d546518562e04af6a1500",
        height: 862825,
        refundAmount: "5301350000000000",
      },
      {
        quote: {
          fedBtcAddress: bs58check
            .decode("3LxPz39femVBL278mTiBvgzBNMVFqXssoH")
            .slice(1),
          lbcAddress: "0xAA9cAf1e3967600578727F975F283446A3Da6612",
          liquidityProviderRskAddress:
            "0x4202bac9919c3412fc7c8be4e678e26279386603",
          btcRefundAddress: bs58check.decode(
            "171gGjg8NeLUonNSrFmgwkgT1jgqzXR6QX"
          ),
          rskRefundAddress: "0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82",
          liquidityProviderBtcAddress: bs58check.decode(
            "17kksixYkbHeLy9okV16kr4eAxVhFkRhP"
          ),
          callFee: "100000000000000",
          penaltyFee: "10000000000000",
          contractAddress: "0xaD0DE1962ab903E06C725A1b343b7E8950a0Ff82",
          data: "0x",
          gasLimit: 21000,
          nonce: "8373381263192041574",
          value: "8000000000000000",
          agreementTimestamp: 1727298699,
          timeForDeposit: 3600,
          callTime: 7200,
          depositConfirmations: 2,
          callOnRegister: false,
          productFeeAmount: 0,
          gasFee: "1341211956000",
        },
        quoteHash:
          "9ef0d0c376a0611ee83a1d938f88cdc8694d9cb6e35780d253fb945e92647d68",
        signature:
          "8ccd018b5c1fb7eceba2a13f8c977ae362c0daccafa6d77a5eb740527dd177620bb6c2d072d68869b3a08b193b1356de564e73233ea1c2686078bf87e3c909a31c",
        btcRawTx:
          "010000000148e9e71dafee5a901be4eceb5aca361c083481b70496f4e3da71e5d969add1820000000017160014b88ef07cd7bcc022b6d73c4764ce5db0887d5b05ffffffff02965c0c000000000017a9141b67149e474f0d7757181f4db89257f27a64738387125b01000000000017a914785c3e807e54dc41251d6377da0673123fa87bc88700000000",
        pmt: "a71100000e7fe369f81a807a962c8e528debd0b46cbfa4f8dfbc02a62674dd41a73f4c4bde0508a9e309e5836703375a58ab116b95434552ca2e460c3273cd2caa13350aefc3c8152a8150f738cd18ff33e69f19b727bff9c2b92aa06e6d0971e9b49893075f2d926bbb9f0884640363b79b6a668a178f140c13f25b48ec975357822ce38c733f6de9b32f6910ff3cd838efd274cd784ab204b74f281ef68146c334f509613d022554f281465dfcd597305c988c4b06e297e5d777afdb66c3391c3c471ebf9a1e051ba38201f08ca758d2dc83a71c34088e6785c1a775e2bde492361462cac9e7042653341cd1e190d0265a33f46ba564dc6116689cf19a8af6816c006df69803008246d44bc849babfbcc3de601fba3d10d696bf4b4d9cb8e291584e7d24bb2c81282972e71cb4493fb4966fcb483d6b62b24a0e25f912ee857d8843e4fa6181b8351f0a300e14503d51f46f367ec872712004535a56f14c65430f044f9685137a1afb2dc0aa402fde8d83b072ef0c4357529466e017dfb2935444103bbeec61bf8944924371921eefd02f35fd5283f3b7bce58a6f4ca15fb32cee8869be8d7720501ec18cc097c236b19212514582212719aede2400b1dd1ff43208ac7504bfb60a00",
        height: 862859,
        refundAmount: "8101340000000000",
      },
    ];
    for (const testCase of cases) {
      /**
       * We perform this modifications because even that these are test cases that happened with actual mainnet
       * transactions, the amounts are too small to be used in regtest, so we need to adapt them to the test environment
       * also, the LBC address is different, so we modify that value as well
       */
      const modifiedQuote = structuredClone(testCase.quote);
      const regtestMultiplier = 100n;
      modifiedQuote.lbcAddress = await lbc.getAddress();
      modifiedQuote.value = BigInt(testCase.quote.value) * regtestMultiplier;
      modifiedQuote.gasFee = BigInt(testCase.quote.gasFee) * regtestMultiplier;
      modifiedQuote.callFee =
        BigInt(testCase.quote.callFee) * regtestMultiplier;
      const modifiedRefundAmount =
        BigInt(testCase.refundAmount) * regtestMultiplier;

      const refundAddressBalanceBefore = await ethers.provider.getBalance(
        modifiedQuote.rskRefundAddress
      );
      const quoteHash = await lbc.hashQuote(modifiedQuote);
      await bridgeMock.setPegin(quoteHash, { value: modifiedRefundAmount });
      const registerTx = await lbc.registerPegIn(
        modifiedQuote,
        "0x" + testCase.signature,
        "0x" + testCase.btcRawTx,
        "0x" + testCase.pmt,
        testCase.height
      );
      const receipt = await registerTx.wait();
      const refundAddressBalanceAfter = await ethers.provider.getBalance(
        modifiedQuote.rskRefundAddress
      );

      expect(receipt!.logs.length).to.be.eq(2);
      expect(refundAddressBalanceAfter - refundAddressBalanceBefore).to.be.eq(
        modifiedRefundAmount
      );
      await expect(registerTx)
        .to.emit(lbc, "Refund")
        .withArgs(
          modifiedQuote.rskRefundAddress,
          modifiedRefundAmount,
          true,
          quoteHash
        );
      await expect(registerTx)
        .to.emit(lbc, "PegInRegistered")
        .withArgs(quoteHash, modifiedRefundAmount);
    }
  });

  it("transfer value and refund remaining", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    let lbc = fixtureResult.lbc;
    const provider = liquidityProviders[1];
    lbc = lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const rskRefundAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: rskRefundAddress,
      value: ethers.parseEther("10"),
    });

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const additionalFunds = 1000000000000n;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);

    await bridgeMock.setPegin(quoteHash, {
      value: peginAmount + additionalFunds,
    });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const destinationBalanceDiffAsserttion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: destinationAddress,
        expectedDiff: quote.value,
        message: "Incorrect destination balance after pegin",
      });
    const lbcBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
      message: "Incorrect LBC balance after pegin",
    });
    const lpBalanceDiffAfterCfuAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: 0,
        message: "Incorrect LP balance after call for user",
      });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: rskRefundAddress,
      expectedDiff: additionalFunds,
      message: "Incorrect refund address balance after refund",
    });
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });

    const cfuTx = await lbc.callForUser(quote, { value: quote.value });
    await cfuTx.wait();

    await lpBalanceDiffAfterCfuAssertion();
    const lpBalanceDiffAfterRegisterAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
        message: "Incorrect LP balance after register pegin",
      });

    const registerPeginResult = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    const registerPeginTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );

    await expect(registerPeginTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount + additionalFunds);
    await expect(registerPeginTx)
      .to.emit(lbc, "Refund")
      .withArgs(rskRefundAddress, additionalFunds, true, quoteHash);
    expect(registerPeginResult).to.be.eq(peginAmount + additionalFunds);
    await destinationBalanceDiffAsserttion();
    await lbcBalanceDiffAssertion();
    await lpBalanceDiffAfterRegisterAssertion();
    await refundBalanceDiffAssertion();
    await collateralAssertion();
  });

  it("refund remaining amount to LP in case refunding to quote.rskRefundAddress fails", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const deploymentInfo = await deployContract("WalletMock", hre.network.name);
    const walletMock = await ethers.getContractAt(
      "WalletMock",
      deploymentInfo.address
    );
    const walletMockAddress = await walletMock.getAddress();
    await walletMock.setRejectFunds(true).then((tx) => tx.wait());
    let lbc = fixtureResult.lbc;
    const provider = liquidityProviders[0];
    lbc = lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const rskRefundAddress = walletMockAddress;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: rskRefundAddress,
      value: ethers.parseEther("10"),
    });

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const additionalFunds = 1000000000000n;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);

    await bridgeMock.setPegin(quoteHash, {
      value: peginAmount + additionalFunds,
    });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const destinationBalanceDiffAssertion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: destinationAddress,
        expectedDiff: quote.value,
        message: "Incorrect destination balance after pegin",
      });
    const lbcBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff:
        peginAmount - BigInt(quote.productFeeAmount) + additionalFunds,
      message: "Incorrect LBC balance after pegin",
    });
    const lpBalanceDiffAfterCfuAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: 0,
        message: "Incorrect LP balance after call for user",
      });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: rskRefundAddress,
      expectedDiff: 0,
      message: "Incorrect refund address balance after refund",
    });
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });

    const cfuTx = await lbc.callForUser(quote, { value: quote.value });
    await cfuTx.wait();
    await lpBalanceDiffAfterCfuAssertion();

    const lpBalanceDiffAfterRegisterAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff:
          peginAmount - BigInt(quote.productFeeAmount) + additionalFunds,
        message: "Incorrect LP balance after register pegin",
      });

    const registerPeginResult = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );

    const registerPeginTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerPeginTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount + additionalFunds);
    await expect(registerPeginTx)
      .to.emit(lbc, "Refund")
      .withArgs(walletMockAddress, additionalFunds, false, quoteHash);
    await expect(registerPeginTx)
      .to.emit(lbc, "BalanceIncrease")
      .withArgs(provider.signer.address, additionalFunds);
    expect(registerPeginResult).to.be.eq(peginAmount + additionalFunds);
    await destinationBalanceDiffAssertion();
    await lbcBalanceDiffAssertion();
    await lpBalanceDiffAfterRegisterAssertion();
    await refundBalanceDiffAssertion();
    await collateralAssertion();
  });

  it("refund user on failed call", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const rskRefundAddress = accounts[2].address;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const deploymentInfo = await deployContract("Mock", hre.network.name);
    const mockContract = await ethers.getContractAt(
      "Mock",
      deploymentInfo.address
    );
    const mockAddress = await mockContract.getAddress();
    const data = mockContract.interface.encodeFunctionData("fail");
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: mockAddress,
      refundAddress: rskRefundAddress,
      value: ethers.parseEther("10"),
      data: data,
    });

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );

    const destinationBalanceDiffAssertion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: mockAddress,
        expectedDiff: 0,
        message: "Incorrect refund balance after pegin",
      });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: rskRefundAddress,
      expectedDiff: quote.value,
      message: "Incorrect refund balance after pegin",
    });
    const lpBalanceDiffAfterCfuAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: quote.value,
        message: "Incorrect LP balance after call for user",
      });
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });

    await lbc
      .callForUser(quote, { value: quote.value })
      .then((tx) => tx.wait());
    await lpBalanceDiffAfterCfuAssertion();

    const lpBalanceDiffAfterRegisterAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: BigInt(quote.callFee) + BigInt(quote.gasFee),
        message: "Incorrect LP balance after register pegin",
      });
    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "Refund")
      .withArgs(rskRefundAddress, quote.value, true, quoteHash);
    await lpBalanceDiffAfterRegisterAssertion();
    await refundBalanceDiffAssertion();
    await collateralAssertion();
    await destinationBalanceDiffAssertion();
  });

  it("refund user on missed call", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const rskRefundAddress = accounts[2].address;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);

    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: accounts[1].address,
      refundAddress: rskRefundAddress,
      value: ethers.parseEther("10"),
    });

    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);

    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const rewardPercentage = await lbc.getRewardPercentage();
    const reward = (BigInt(quote.penaltyFee) * rewardPercentage) / 100n;

    const destinationBalanceDiffAssertion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: accounts[1].address,
        expectedDiff: 0,
        message: "Incorrect refund balance after pegin",
      });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: rskRefundAddress,
      expectedDiff:
        BigInt(quote.value) + BigInt(quote.callFee) + BigInt(quote.gasFee),
      message: "Incorrect refund balance after pegin",
    });
    const lpBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: reward,
      message: "Incorrect LP balance after call for user",
    });
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: BigInt(quote.penaltyFee) * -1n,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const lbcBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff: 0,
      message: "Incorrect LBC balance after pegin",
    });

    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "Refund")
      .withArgs(rskRefundAddress, peginAmount, true, quoteHash);
    await destinationBalanceDiffAssertion();
    await refundBalanceDiffAssertion();
    await lpBalanceDiffAssertion();
    await collateralAssertion();
    await lbcBalanceDiffAssertion();
  });

  it("no one be refunded in registerPegIn on missed call in case refunding to quote.rskRefundAddress fails", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const deploymentInfo = await deployContract("WalletMock", hre.network.name);
    const walletMock = await ethers.getContractAt(
      "WalletMock",
      deploymentInfo.address
    );
    const walletMockAddress = await walletMock.getAddress();
    await walletMock.setRejectFunds(true).then((tx) => tx.wait());
    const destinationAddress = accounts[1].address;
    const registerCaller = accounts[2];
    const lbc = fixtureResult.lbc.connect(registerCaller);
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: walletMockAddress,
      value: ethers.parseEther("10"),
    });
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const rewardPercentage = await lbc.getRewardPercentage();
    const reward = (BigInt(quote.penaltyFee) * rewardPercentage) / 100n;
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;

    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(10, firstConfirmationHeader);
    await bridgeMock.setHeader(11, nConfirmationHeader);

    const registerCallerBalanceDiffAssertion =
      await createBalanceDifferenceAssertion({
        source: lbc,
        expectedDiff: reward,
        address: registerCaller.address,
        message: "Incorrect refund balance after pegin",
      });
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: BigInt(quote.penaltyFee) * -1n,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: walletMockAddress,
      expectedDiff: 0,
      message: "Incorrect refund balance after pegin",
    });
    const lbcBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff: peginAmount - BigInt(quote.productFeeAmount),
      message: "Incorrect LBC balance after pegin",
    });

    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "Refund")
      .withArgs(
        walletMockAddress,
        peginAmount - BigInt(quote.productFeeAmount),
        false,
        quoteHash
      );
    await collateralAssertion();
    await refundBalanceDiffAssertion();
    await lbcBalanceDiffAssertion();
    await registerCallerBalanceDiffAssertion();
  });

  it("not penalize with late deposit", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const refundAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: accounts[1].address,
      refundAddress: refundAddress,
      value: ethers.parseEther("10"),
    });
    quote.timeForDeposit = 1;

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const peginAmount = totalValue(quote);
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;

    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: refundAddress,
      expectedDiff: peginAmount,
      message: "Incorrect destination balance after pegin",
    });
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, peginAmount);
    await expect(registerTx).not.to.emit(lbc, "Penalized");
    await collateralAssertion();
    await refundBalanceDiffAssertion();
  });

  it("not penalize with insufficient deposit", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const refundAddress = accounts[2].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: accounts[1].address,
      refundAddress: refundAddress,
      value: ethers.parseEther("10"),
    });

    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const peginAmount = totalValue(quote);
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const insufficientDeposit = peginAmount - 1n;
    await bridgeMock.setPegin(quoteHash, { value: insufficientDeposit });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const refundBalanceDiffAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: refundAddress,
      expectedDiff: insufficientDeposit,
      message: "Incorrect destination balance after pegin",
    });
    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "PegInRegistered")
      .withArgs(quoteHash, insufficientDeposit);
    await expect(registerTx).not.to.emit(lbc, "Penalized");
    await collateralAssertion();
    await refundBalanceDiffAssertion();
  });

  it("should penalize on late call", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: accounts[2].address,
      value: ethers.parseEther("10"),
    });
    quote.callTime = 1;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 200,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const rewardPercentage = await lbc.getRewardPercentage();
    const reward = (BigInt(quote.penaltyFee) * rewardPercentage) / 100n;
    await hardhatHelpers.time.increase(300);
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: BigInt(quote.penaltyFee) * -1n,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const destinationBalanceDiffAssertion =
      await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: destinationAddress,
        expectedDiff: quote.value,
        message: "Incorrect destination balance after pegin",
      });
    const lpBalanceAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: reward + peginAmount,
      message: "Incorrect LP balance after call for user",
    });

    await lbc
      .callForUser(quote, { value: quote.value })
      .then((tx) => tx.wait());

    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "Penalized")
      .withArgs(provider.signer.address, quote.penaltyFee, quoteHash);
    await collateralAssertion();
    await destinationBalanceDiffAssertion();
    await lpBalanceAssertion();
  });

  it("not underflow when penalty is higher than collateral", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: accounts[2].address,
      value: ethers.parseEther("10"),
    });
    quote.penaltyFee = LP_COLLATERAL + 1n;
    quote.callTime = 1;
    const peginAmount = totalValue(quote);
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 200,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    const rewardPercentage = await lbc.getRewardPercentage();
    const reward = (BigInt(quote.penaltyFee / 2n) * rewardPercentage) / 100n;
    await hardhatHelpers.time.increase(300);

    const lpBalanceAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: reward + peginAmount - BigInt(quote.productFeeAmount),
      message: "Incorrect LP balance after pegin",
    });
    const userBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: destinationAddress,
      expectedDiff: quote.value,
      message: "Incorrect destination balance after pegin",
    });
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await lbc
      .callForUser(quote, { value: quote.value })
      .then((tx) => tx.wait());
    const registerTx = await lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx)
      .to.emit(lbc, "Penalized")
      .withArgs(provider.signer.address, LP_COLLATERAL / 2n, quoteHash);
    await lpBalanceAssertion();
    await userBalanceAssertion();
    await expect(
      lbc.getCollateral(provider.signer.address)
    ).to.eventually.be.eq(0);
  });

  it("should not allow attacker to steal funds", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, accounts, bridgeMock } = fixtureResult;
    let { lbc } = fixtureResult;

    // The attacker controls a liquidity provider and also a destination address
    // Note that these could be the same address, separated for clarity
    const attackingLP = liquidityProviders[0];
    const attackerDestAddress = accounts[9];

    const goodLP = liquidityProviders[1];
    // Add funds from an innocent liquidity provider, note again this could be
    // done by an attacker
    lbc = lbc.connect(goodLP.signer);
    await lbc.deposit({ value: ethers.parseEther("20") });

    // The quote value in wei should be bigger than 2**63-1. 10 RBTC is a good approximation.
    const quoteValue = ethers.parseEther("10");
    // Let's create the evil quote.
    const quote: QuotesV2.PeginQuoteStruct = {
      fedBtcAddress: "0x0000000000000000000000000000000000000000",
      btcRefundAddress: "0x000000000000000000000000000000000000000000",
      liquidityProviderBtcAddress:
        "0x000000000000000000000000000000000000000000",
      rskRefundAddress: attackerDestAddress,
      liquidityProviderRskAddress: attackerDestAddress,
      data: "0x",
      gasLimit: 30000,
      callFee: 1n,
      nonce: 1,
      lbcAddress: await lbc.getAddress(),
      agreementTimestamp: 1661788988,
      timeForDeposit: 600,
      callTime: 600,
      depositConfirmations: 10,
      penaltyFee: 0n,
      callOnRegister: true,
      productFeeAmount: 1,
      gasFee: 1n,
      value: quoteValue,
      contractAddress: attackerDestAddress,
    };
    const btcRawTransaction = "0x0101";
    const partialMerkleTree = "0x0202";
    const height = 10;
    // Let's now register our quote in the bridge... note that the
    // value is only a hundred wei
    const transferredInBTC = 100;
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await attackingLP.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 300,
        nConfirmationSeconds: 600,
      });
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) - 1,
      nConfirmationHeader
    );
    await bridgeMock.setPegin(quoteHash, { value: transferredInBTC });
    lbc = lbc.connect(attackingLP.signer);
    const registerTx = lbc.registerPegIn(
      quote,
      signature,
      btcRawTransaction,
      partialMerkleTree,
      height
    );
    await expect(registerTx).to.be.revertedWith("LBC057");
  });

  it("pay with insufficient deposit that is not lower than (agreed amount - delta)", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: accounts[2].address,
      value: ethers.parseEther("0.7"),
    });
    quote.callFee = ethers.parseEther("0.00001");
    quote.gasFee = ethers.parseEther("0.00003");
    const delta = totalValue(quote) / 10000n;
    const peginAmount = totalValue(quote) - delta;
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 200,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) + 1,
      nConfirmationHeader
    );
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });

    const collateralAssertion = await createCollateralUpdateAssertion({
      lbc: lbc,
      address: provider.signer.address,
      expectedDiff: 0,
      message: "Incorrect collateral after pegin",
      type: "pegin",
    });
    const lpBalanceAssertion = await createBalanceDifferenceAssertion({
      source: lbc,
      address: provider.signer.address,
      expectedDiff: peginAmount,
      message: "Incorrect LP balance after pegin",
    });
    const lbcBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: await lbc.getAddress(),
      expectedDiff: peginAmount,
      message: "Incorrect LBC balance after pegin",
    });
    const destinationBalanceAssertion = await createBalanceDifferenceAssertion({
      source: ethers.provider,
      address: destinationAddress,
      expectedDiff: quote.value,
      message: "Incorrect destination balance after pegin",
    });

    await lbc
      .callForUser(quote, { value: quote.value })
      .then((tx) => tx.wait());

    const registerResult = await lbc.registerPegIn.staticCall(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await lbc
      .registerPegIn(
        quote,
        signature,
        blockHeaderHash,
        partialMerkleTree,
        height
      )
      .then((tx) => tx.wait());
    expect(registerResult).to.be.eq(peginAmount);
    await collateralAssertion();
    await lpBalanceAssertion();
    await lbcBalanceAssertion();
    await destinationBalanceAssertion();
  });

  it("revert on insufficient deposit", async () => {
    const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
    const { liquidityProviders, bridgeMock, accounts } = fixtureResult;
    const provider = liquidityProviders[0];
    const lbc = fixtureResult.lbc.connect(provider.signer);
    const destinationAddress = accounts[1].address;
    const quote = getTestPeginQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: provider.signer,
      destinationAddress: destinationAddress,
      refundAddress: accounts[2].address,
      value: ethers.parseEther("0.7"),
    });
    quote.callFee = ethers.parseEther("0.000005");
    quote.gasFee = ethers.parseEther("0.000006");
    const delta = totalValue(quote) / 10000n;
    const peginAmount = totalValue(quote) - delta - 1n;
    const quoteHash = await lbc.hashQuote(quote).then((hash) => getBytes(hash));
    const signature = await provider.signer.signMessage(quoteHash);
    const { firstConfirmationHeader, nConfirmationHeader } =
      getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 200,
      });
    const { blockHeaderHash, partialMerkleTree } = getTestMerkleProof();
    const height = 10;
    await bridgeMock.setHeader(height, firstConfirmationHeader);
    await bridgeMock.setHeader(
      height + Number(quote.depositConfirmations) + 1,
      nConfirmationHeader
    );
    await bridgeMock.setPegin(quoteHash, { value: peginAmount });
    const registerTx = lbc.registerPegIn(
      quote,
      signature,
      blockHeaderHash,
      partialMerkleTree,
      height
    );
    await expect(registerTx).to.be.revertedWith("LBC057");
  });
});
