import hre from "hardhat";
import { ethers } from "hardhat";
import {
  anyHex,
  anyNumber,
  LP_COLLATERAL,
  MIN_COLLATERAL_TEST,
  REGISTER_LP_PARAMS,
  RegisterLpParams,
  ZERO_ADDRESS,
} from "./utils/constants";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { deployContract } from "../scripts/deployment-utils/utils";
import {
  deployLbcFixture,
  deployLbcWithProvidersFixture,
} from "./utils/fixtures";
import {
  getBtcPaymentBlockHeaders,
  getTestPeginQuote,
  getTestPegoutQuote,
  totalValue,
} from "./utils/quotes";
import { getBytes, hexlify } from "ethers";
import {
  createBalanceDifferenceAssertion,
  createBalanceUpdateAssertion,
  createCollateralUpdateAssertion,
} from "./utils/asserts";
import {
  BtcAddressType,
  generateRawTx,
  getTestMerkleProof,
  weiToSat,
} from "./utils/btc";
import { fromLeHex } from "./utils/encoding";
import * as bs58check from "bs58check";
import bs58 from "bs58";
import * as hardhatHelpers from "@nomicfoundation/hardhat-network-helpers";
import { read } from "../scripts/deployment-utils/deploy";
import { QuotesV2 } from "../typechain-types";

describe("LiquidityBridgeContractV2", function () {
  describe("registration process should", () => {
    it("register liquidity provider successfully", async () => {
      const fixtureResult = await loadFixture(deployLbcFixture);
      const lpAccount = fixtureResult.accounts[0];
      let lbc = fixtureResult.lbc;

      const previousCollateral = await lbc.getCollateral(lpAccount);
      lbc = lbc.connect(lpAccount);

      const tx = await lbc.register(...REGISTER_LP_PARAMS);
      await tx.wait();
      const currentCollateral = await lbc.getCollateral(lpAccount);

      await expect(tx)
        .to.emit(lbc, "Register")
        .withArgs(1n, lpAccount.address, LP_COLLATERAL);
      expect(2n * (currentCollateral - previousCollateral)).to.be.eq(
        LP_COLLATERAL
      );
    });

    it("fail on register if bad parameters", async () => {
      const { lbc } = await loadFixture(deployLbcFixture);
      const cases = [
        {
          name: "",
          url: "http://localhost/api",
          status: true,
          type: "both",
          error: "LBC010",
        },
        {
          name: "First contract",
          url: "",
          status: true,
          type: "both",
          error: "LBC017",
        },
        {
          name: "First contract",
          url: "http://localhost/api",
          status: true,
          type: "",
          error: "LBC018",
        },
      ];

      for (const testCase of cases) {
        await expect(
          lbc.register(
            testCase.name,
            testCase.url,
            testCase.status,
            testCase.type,
            { value: LP_COLLATERAL }
          )
        ).to.be.revertedWith(testCase.error);
      }
    });

    it("fail when Liquidity provider is already registered", async () => {
      const fixtureResult = await loadFixture(deployLbcFixture);
      const lpAccount = fixtureResult.accounts[5];
      const lbc = fixtureResult.lbc.connect(lpAccount);

      const tx = await lbc.register(...REGISTER_LP_PARAMS);
      await expect(tx)
        .to.emit(lbc, "Register")
        .withArgs(1n, lpAccount.address, LP_COLLATERAL);
      await expect(lbc.register(...REGISTER_LP_PARAMS)).to.revertedWith(
        "LBC070"
      );
    });

    it("fail on register if not deposit the minimum collateral", async () => {
      const { lbc } = await loadFixture(deployLbcFixture);
      await expect(
        lbc.register("First contract", "http://localhost/api", true, "both", {
          value: 0n,
        })
      ).to.be.revertedWith("LBC008");
    });

    it("not register lp with not enough collateral", async () => {
      const { lbc } = await loadFixture(deployLbcFixture);
      await expect(
        lbc.register("First contract", "http://localhost/api", true, "both", {
          value: MIN_COLLATERAL_TEST * 2n - 1n,
        })
      ).to.be.revertedWith("LBC008");
    });

    it("fail to register liquidity provider from a contract", async () => {
      const fixtureResult = await loadFixture(deployLbcFixture);
      const accounts = fixtureResult.accounts;
      const lpSigner = accounts[9];
      const notLpSigner = accounts[8];
      let lbc = fixtureResult.lbc;
      const deploymentInfo = await deployContract("Mock", hre.network.name);
      let mockContract = await ethers.getContractAt(
        "Mock",
        deploymentInfo.address
      );
      const lbcAddress = await lbc.getAddress();

      lbc = lbc.connect(lpSigner);
      const tx = await lbc.register(...REGISTER_LP_PARAMS);
      await tx.wait();

      mockContract = await mockContract.connect(lpSigner);
      await expect(
        mockContract.callRegister(lbcAddress, { value: LP_COLLATERAL })
      ).to.revertedWith("LBC003");

      mockContract = await mockContract.connect(notLpSigner);
      await expect(
        mockContract.callRegister(lbcAddress, { value: LP_COLLATERAL })
      ).to.revertedWith("LBC003");
    });
  });

  describe("provider discovery should", () => {
    it("list registered providers", async () => {
      const { lbc, liquidityProviders } = await loadFixture(
        deployLbcWithProvidersFixture
      );
      const providerList = await lbc.getProviders();
      expect(providerList.length).to.be.eq(3);
      providerList.forEach((p, i) => {
        expect(p.id).to.be.eq(i + 1);
        expect(p.provider).to.be.eq(liquidityProviders[i].signer.address);
        expect(p.name).to.be.eq(liquidityProviders[i].registerParams[0]);
        expect(p.apiBaseUrl).to.be.eq(liquidityProviders[i].registerParams[1]);
        expect(p.status).to.be.eq(liquidityProviders[i].registerParams[2]);
        expect(p.providerType).to.be.eq(
          liquidityProviders[i].registerParams[3]
        );
      });
    });

    it("get the last provider id", async () => {
      const { lbc, liquidityProviders } = await loadFixture(
        deployLbcWithProvidersFixture
      );
      const lastProviderId = await lbc.getProviderIds();
      expect(lastProviderId).to.be.eq(liquidityProviders.length);
    });

    it("allow a provider to disable by itself", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const lp = fixtureResult.liquidityProviders[1];
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(lp.signer);
      await lbc.setProviderStatus(2, false);
      const provider = await lbc.getProvider(lp.signer.address);
      expect(provider.status).to.be.eq(false);
    });

    it("fail if provider does not exist", async () => {
      const { lbc, liquidityProviders, accounts } = await loadFixture(
        deployLbcWithProvidersFixture
      );
      const notLpSigner = accounts[0];
      expect(
        liquidityProviders.some(
          (lp) => lp.signer.address === notLpSigner.address
        )
      ).to.be.eq(false);
      await expect(lbc.getProvider(notLpSigner.address)).to.be.revertedWith(
        "LBC001"
      );
    });

    it("return correct state of a provider", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const [lp1, lp2] = fixtureResult.liquidityProviders;
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(lp1.signer);
      const tx = await lbc.setProviderStatus(1, false);
      await tx.wait();
      let provider = await lbc.getProvider(lp1.signer.address);
      expect(provider.status).to.be.eq(false);
      expect(provider.name).to.be.equal("First LP");
      expect(provider.apiBaseUrl).to.be.equal("http://localhost/api1");
      expect(provider.provider).to.be.equal(lp1.signer.address);
      expect(provider.providerType).to.be.equal("both");
      provider = await lbc.getProvider(lp2.signer.address);
      expect(provider.status).to.be.eq(true);
      expect(provider.name).to.be.equal("Second LP");
      expect(provider.apiBaseUrl).to.be.equal("http://localhost/api2");
      expect(provider.provider).to.be.equal(lp2.signer.address);
      expect(provider.providerType).to.be.equal("pegin");
    });

    it("allow a provider to enable by itself", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const lp = fixtureResult.liquidityProviders[1];
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(lp.signer);

      await lbc.setProviderStatus(2, false);
      let provider = await lbc.getProvider(lp.signer.address);
      expect(provider.status).to.be.eq(false);

      await lbc.setProviderStatus(2, true);
      provider = await lbc.getProvider(lp.signer.address);
      expect(provider.status).to.be.eq(true);
    });
    it("disable and enable provider as LBC owner", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, lbcOwner } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const lp = liquidityProviders[1];
      lbc = lbc.connect(lbcOwner);

      await lbc.setProviderStatus(2, false);
      let provider = await lbc.getProvider(lp.signer.address);
      expect(provider.status).to.be.eq(false);

      await lbc.setProviderStatus(2, true);
      provider = await lbc.getProvider(lp.signer.address);
      expect(provider.status).to.be.eq(true);
    });

    it("fail disabling provider as non owners", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const lp = fixtureResult.liquidityProviders[0]; // the id of this provider is 1
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(lp.signer);
      await expect(lbc.setProviderStatus(2, false)).to.be.revertedWith(
        "LBC005"
      );
    });

    it("update the liquidity provider information correctly", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;

      const providerIndex = 1;
      const providerSigner = liquidityProviders[providerIndex].signer;
      let provider = await lbc
        .getProviders()
        .then((result) => result[providerIndex]);

      const initialState = {
        id: provider.id,
        provider: provider.provider,
        name: provider.name,
        apiBaseUrl: provider.apiBaseUrl,
        status: provider.status,
        providerType: provider.providerType,
      };

      const newName = "modified name";
      const newApiBaseUrl = "https://modified.com";

      lbc = lbc.connect(providerSigner);
      const tx = await lbc.updateProvider(newName, newApiBaseUrl);
      await expect(tx)
        .to.emit(lbc, "ProviderUpdate")
        .withArgs(providerSigner.address, newName, newApiBaseUrl);

      provider = await lbc
        .getProviders()
        .then((result) => result[providerIndex]);
      const finalState = {
        id: provider.id,
        provider: provider.provider,
        name: provider.name,
        apiBaseUrl: provider.apiBaseUrl,
        status: provider.status,
        providerType: provider.providerType,
      };

      expect(initialState.id).to.be.eq(finalState.id);
      expect(initialState.provider).to.be.eq(finalState.provider);
      expect(initialState.status).to.be.eq(finalState.status);
      expect(initialState.providerType).to.be.eq(finalState.providerType);
      expect(initialState.name).to.not.be.eq(finalState.name);
      expect(initialState.apiBaseUrl).to.not.be.eq(finalState.apiBaseUrl);
      expect(finalState.name).to.be.eq(newName);
      expect(finalState.apiBaseUrl).to.be.eq(newApiBaseUrl);
    });

    it("fail if unregistered provider updates his information", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts } = fixtureResult;
      const provider = accounts[5];
      const lbc = fixtureResult.lbc.connect(provider);
      const newName = "not-existing name";
      const newApiBaseUrl = "https://not-existing.com";
      const tx = lbc.updateProvider(newName, newApiBaseUrl);
      await expect(tx).to.be.revertedWith("LBC001");
    });

    it("fail if provider makes update with invalid information", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders } = fixtureResult;
      const provider = liquidityProviders[2];
      const lbc = fixtureResult.lbc.connect(provider.signer);
      const newName = "any name";
      const newApiBaseUrl = "https://any.com";
      const wrongName = lbc.updateProvider("", newApiBaseUrl);
      await expect(wrongName).to.be.revertedWith("LBC076");
      const wrongUrl = lbc.updateProvider(newName, "");
      await expect(wrongUrl).to.be.revertedWith("LBC076");
    });

    it("list enabled and not resigned providers only", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts } = fixtureResult;
      let lbc = fixtureResult.lbc;
      /**
       * Target provider statuses per account:
       * 0 - lbc owner (not a provider)
       *
       * accounts array
       * 1 - active (LP 4)
       * 2 - not a provider
       * 3 - resigned and disabled (LP 5)
       * 4 - disabled (LP 6)
       * 5 - active (LP 7)
       * 6 - resigned but active (LP 8)
       *
       * LPs array
       * 7 - active (LP 1)
       * 8 - disabled (LP 2)
       * 9 - active (LP 3)
       */

      // Prepare the expected statuses
      lbc = lbc.connect(liquidityProviders[1].signer);
      await lbc.setProviderStatus(2, false);

      const newLps = [0, 2, 3, 4, 5].map((i) => ({
        signer: accounts[i],
        accountIdx: i,
      }));
      for (const lp of newLps) {
        lbc = lbc.connect(lp.signer);
        const params: RegisterLpParams = [...REGISTER_LP_PARAMS];
        params[0] = `LP account ${lp.accountIdx}`;
        params[1] = `${params[1]}-account${lp.accountIdx}`;
        const registerTx = await lbc.register(...params);
        await expect(registerTx).to.emit(lbc, "Register");
      }

      lbc = lbc.connect(newLps[1].signer);
      await lbc.setProviderStatus(5, false).then((tx) => tx.wait());
      await lbc.resign().then((tx) => tx.wait());

      lbc = lbc.connect(newLps[2].signer);
      await lbc.setProviderStatus(6, false).then((tx) => tx.wait());

      lbc = lbc.connect(newLps[4].signer);
      await lbc.resign().then((tx) => tx.wait());

      lbc = lbc.connect(accounts[1]);
      const result = await lbc.getProviders();
      expect(result.length).to.be.eq(4);
      expect(result[0]).to.be.deep.equal([
        1n,
        liquidityProviders[0].signer.address,
        "First LP",
        "http://localhost/api1",
        true,
        "both",
      ]);
      expect(result[1]).to.be.deep.equal([
        3n,
        liquidityProviders[2].signer.address,
        "Third LP",
        "http://localhost/api3",
        true,
        "pegout",
      ]);
      expect(result[2]).to.be.deep.equal([
        4n,
        accounts[0].address,
        "LP account 0",
        "http://localhost/api-account0",
        true,
        "both",
      ]);
      expect(result[3]).to.be.deep.equal([
        7n,
        accounts[4].address,
        "LP account 4",
        "http://localhost/api-account4",
        true,
        "both",
      ]);
    });
  });

  describe("quotes management should", () => {
    it("match LP address with address retrieved from ecrecover", async () => {
      const { lbc, liquidityProviders } = await loadFixture(
        deployLbcWithProvidersFixture
      );

      const deploymentInfo = await deployContract(
        "SignatureValidator",
        hre.network.name
      );
      const signatureValidator = await ethers.getContractAt(
        "SignatureValidator",
        deploymentInfo.address
      );

      const provider = liquidityProviders[0];
      const destinationAddress = await ethers
        .getSigners()
        .then((accounts) => accounts[0].address);
      const quote = getTestPeginQuote({
        lbcAddress: await lbc.getAddress(),
        liquidityProvider: provider.signer,
        destinationAddress: destinationAddress,
        refundAddress: destinationAddress,
        value: ethers.parseEther("0.5"),
      });

      const quoteHash = await lbc
        .hashQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      const signatureAddress = ethers.verifyMessage(quoteHash, signature);
      const validSignature = await signatureValidator.verify(
        provider.signer.address,
        quoteHash,
        signature
      );

      expect(signatureAddress).to.be.equal(provider.signer.address);
      expect(validSignature).to.be.eq(true);
    });
  });

  describe("pegin process should", () => {
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
      const lpBalanceAfterCfuAssertion = await createBalanceDifferenceAssertion(
        {
          source: lbc,
          address: provider.signer.address,
          expectedDiff: 0,
          message: "Incorrect LP balance after callForUser",
        }
      );
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

      const quoteHash = await lbc
        .hashQuote(quote)
        .then((hash) => getBytes(hash));
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

      const feeCollectorBalanceAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: ZERO_ADDRESS,
          expectedDiff: daoFee,
          message: "Incorrect DAO fee collector balance after pegin",
        });

      const lpBalanceAfterCfuAssertion = await createBalanceDifferenceAssertion(
        {
          source: lbc,
          address: provider.signer.address,
          expectedDiff: 0,
          message: "Incorrect LP balance after call for user",
        }
      );

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

      const quoteHash = await lbc
        .hashQuote(quote)
        .then((hash) => getBytes(hash));
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

      const feeCollectorBalanceAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: ZERO_ADDRESS,
          expectedDiff: 0,
          message: "Incorrect DAO fee collector balance after pegin",
        });

      const quoteHash = await lbc
        .hashQuote(quote)
        .then((hash) => getBytes(hash));
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
          address: "2MxwA285sNe1ZLXttmnLjHesF78ReuHndeB",
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
          address: "2MtBe6G5ZoHE3exeXC5uebqgtePu8DQSjEd",
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
          address: "2NDMRpF5otmL7urZEHNWENFZR7QfzdV6kCX",
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
      type testCase = {
        quote: QuotesV2.PeginQuoteStruct;
        quoteHash: string;
        signature: string;
        btcRawTx: string;
        pmt: string;
        height: number;
        refundAmount: string;
      };
      const cases: testCase[] = [
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
        modifiedQuote.gasFee =
          BigInt(testCase.quote.gasFee) * regtestMultiplier;
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
  });

  describe("liquidity management should", () => {
    it("fail when withdraw amount greater than the sender balance", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const provider = fixtureResult.liquidityProviders[0];
      let lbc = fixtureResult.lbc;

      lbc = lbc.connect(provider.signer);
      const depositTx = await lbc.deposit({ value: "100000000" });
      await depositTx.wait();
      const firstWithdrawTx = lbc.withdraw("999999999999999");
      await expect(firstWithdrawTx).to.be.revertedWith("LBC019");
      const secondWithdrawTx = lbc.withdraw("100000000");
      await expect(secondWithdrawTx).not.to.be.reverted;
    });

    it("deposit a value to increase balance of liquidity provider", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const provider = fixtureResult.liquidityProviders[1];
      const value = 100000000n;
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(provider.signer);

      const balanceAssertion = await createBalanceDifferenceAssertion({
        source: lbc,
        address: provider.signer.address,
        expectedDiff: value,
        message: "Incorrect LP balance after deposit",
      });
      const tx = await lbc.deposit({ value });
      await expect(tx)
        .to.emit(lbc, "BalanceIncrease")
        .withArgs(provider.signer.address, value);
      await balanceAssertion();
    });
  });

  describe("resignation process should", () => {
    it("fail when liquidityProdvider try to withdraw collateral without resign postion as liquidity provider before", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const provider = fixtureResult.liquidityProviders[1];
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(provider.signer);

      await expect(lbc.withdrawCollateral()).to.be.revertedWith("LBC021");
      const resignBlocks = await lbc.getResignDelayBlocks();
      await lbc.resign();
      await hardhatHelpers.mine(resignBlocks);
      await expect(lbc.withdrawCollateral()).not.to.be.reverted;
    });

    it("fail when LP resigns two times", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const provider = fixtureResult.liquidityProviders[1];
      let lbc = fixtureResult.lbc;
      const resignBlocks = await lbc.getResignDelayBlocks();
      lbc = lbc.connect(provider.signer);
      await expect(lbc.resign()).not.to.be.reverted;
      await expect(lbc.resign()).to.be.revertedWith("LBC001");
      await hardhatHelpers.mine(resignBlocks);
      await expect(lbc.withdrawCollateral()).not.to.be.reverted;
    });

    it("should resign", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const provider = fixtureResult.liquidityProviders[0];
      let lbc = fixtureResult.lbc;
      lbc = lbc.connect(provider.signer);
      const lpBalance = ethers.parseEther("0.5");
      await lbc.deposit({ value: lpBalance });
      const resignBlocks = await lbc.getResignDelayBlocks();

      const lbcBalanceAfterResignAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: 0,
          message: "Incorrect LBC balance after resign",
        });

      const lbcBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: lpBalance * -1n,
          message: "Incorrect LBC balance after withdraw",
        });

      const lpBalanceAfterWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: provider.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lpProtocolBalanceAfterWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: provider.signer.address,
          expectedDiff: lpBalance * -1n,
          message: "Incorrect LP balance in LBC after withdraw",
        });

      const peginCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: provider.signer.address,
          expectedDiff: (LP_COLLATERAL / 2n) * -1n,
          message: "Incorrect pegin collateral after withdraw",
          type: "pegin",
        });

      const pegoutCollateralAfterWithdrawAssertion =
        await createCollateralUpdateAssertion({
          lbc: lbc,
          address: provider.signer.address,
          expectedDiff: (LP_COLLATERAL / 2n) * -1n,
          message: "Incorrect pegout collateral after withdraw",
          type: "pegout",
        });

      const resignTx = await lbc.resign();
      const resignReceipt = await resignTx.wait();

      await lbcBalanceAfterResignAssertion();

      const withdrawTx = await lbc.withdraw(lpBalance);
      const withdrawReceipt = await withdrawTx.wait();

      await expect(resignTx)
        .to.emit(lbc, "Resigned")
        .withArgs(provider.signer.address);
      await expect(withdrawTx)
        .to.emit(lbc, "Withdrawal")
        .withArgs(provider.signer.address, lpBalance);

      await lbcBalanceAfterWithdrawAssertion();
      await lpBalanceAfterWithdrawAssertion(
        lpBalance - withdrawReceipt!.fee - resignReceipt!.fee
      );
      await lpProtocolBalanceAfterWithdrawAssertion();

      const lpBalanceAfterCollateralWithdrawAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: provider.signer.address,
          message: "Incorrect LP balance after withdraw",
        });

      const lbcBalanceAfterCollateralWithdrawAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: LP_COLLATERAL * -1n,
          message: "Incorrect LBC balance after collateral withdraw",
        });

      await hardhatHelpers.mine(resignBlocks);

      const withdrawCollateralTx = await lbc.withdrawCollateral();
      const withdrawCollateralReceipt = await withdrawCollateralTx.wait();

      await expect(withdrawCollateralTx)
        .to.emit(lbc, "WithdrawCollateral")
        .withArgs(provider.signer.address, LP_COLLATERAL);
      await lpBalanceAfterCollateralWithdrawAssertion(
        LP_COLLATERAL - withdrawCollateralReceipt!.fee
      );
      await peginCollateralAfterWithdrawAssertion();
      await pegoutCollateralAfterWithdrawAssertion();
      await lbcBalanceAfterCollateralWithdrawAssertion();
      await expect(
        lbc.getCollateral(provider.signer.address)
      ).to.eventually.be.eq(0);
      await expect(
        lbc.getPegoutCollateral(provider.signer.address)
      ).to.eventually.be.eq(0);
    });
  });

  describe("pegout process should", () => {
    (
      ["p2pkh", "p2sh", "p2wpkh", "p2wsh", "p2tr"] satisfies BtcAddressType[]
    ).forEach((scriptType) => {
      it(`refundPegOut for a ${scriptType.toUpperCase()} transaction`, async () => {
        const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
        const { liquidityProviders, accounts } = fixtureResult;
        const provider = liquidityProviders[0];
        const user = accounts[0];
        const bridgeMock = fixtureResult.bridgeMock.connect(provider.signer);
        let lbc = fixtureResult.lbc;
        lbc = lbc.connect(provider.signer);
        const daoFee = 100000000000n;
        const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
          getTestMerkleProof();
        const quote = getTestPegoutQuote({
          lbcAddress: await lbc.getAddress(),
          value: ethers.parseEther("0.5"),
          refundAddress: user.address,
          liquidityProvider: liquidityProviders[0].signer,
          destinationAddressType: scriptType,
        });
        quote.productFeeAmount = daoFee;
        const pegoutAmount = totalValue(quote);

        const lpBalanceDiffAfterDepositAssertion =
          await createBalanceDifferenceAssertion({
            source: lbc,
            address: provider.signer.address,
            expectedDiff: 0,
            message: "Incorrect LP balance after deposit",
          });
        const lbcBalanceDiffAfterDepositAssertion =
          await createBalanceDifferenceAssertion({
            source: ethers.provider,
            address: await lbc.getAddress(),
            expectedDiff: pegoutAmount,
            message: "Incorrect LBC balance after deposit",
          });
        const userBalanceAfterDepositAssertion =
          await createBalanceUpdateAssertion({
            source: ethers.provider,
            address: user.address,
            message: "Incorrect user balance after deposit",
          });

        const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
          quote: quote,
          firstConfirmationSeconds: 100,
          nConfirmationSeconds: 600,
        });
        await bridgeMock.setHeaderByHash(
          blockHeaderHash,
          firstConfirmationHeader
        );
        const quoteHash = await lbc
          .hashPegoutQuote(quote)
          .then((hash) => getBytes(hash));
        const signature = await provider.signer.signMessage(quoteHash);
        lbc = lbc.connect(user);
        const depositTx = await lbc.depositPegout(quote, signature, {
          value: pegoutAmount,
        });
        const depositReceipt = await depositTx.wait();

        await expect(depositTx).to.emit(lbc, "PegOutDeposit");
        await lpBalanceDiffAfterDepositAssertion();
        await lbcBalanceDiffAfterDepositAssertion();
        await userBalanceAfterDepositAssertion(
          (pegoutAmount + depositReceipt!.fee) * -1n
        );

        const btcTx = await generateRawTx(lbc, quote, scriptType);

        const lpBalanceAfterRefundAssertion =
          await createBalanceUpdateAssertion({
            source: ethers.provider,
            address: provider.signer.address,
            message: "Incorrect LP balance after refund",
          });
        const lbcBalanceDiffAfterRefundAssertion =
          await createBalanceDifferenceAssertion({
            source: ethers.provider,
            address: await lbc.getAddress(),
            expectedDiff: pegoutAmount * -1n,
            message: "Incorrect LBC balance after refund",
          });
        const userBalanceDiffAfterRefundAssertion =
          await createBalanceDifferenceAssertion({
            source: ethers.provider,
            address: user.address,
            expectedDiff: 0,
            message: "Incorrect user balance after refund",
          });

        lbc = lbc.connect(provider.signer);
        const refundTx = await lbc.refundPegOut(
          quoteHash,
          btcTx,
          blockHeaderHash,
          partialMerkleTree,
          merkleBranchHashes
        );
        const refundReceipt = await refundTx.wait();
        await expect(refundTx)
          .to.emit(lbc, "PegOutRefunded")
          .withArgs(quoteHash);
        await expect(refundTx).not.to.emit(lbc, "Penalized");
        await expect(refundTx)
          .to.emit(lbc, "DaoFeeSent")
          .withArgs(quoteHash, daoFee);
        await expect(ethers.provider.getBalance(ZERO_ADDRESS)).to.eventually.eq(
          daoFee
        );
        await lpBalanceAfterRefundAssertion(
          pegoutAmount - BigInt(quote.productFeeAmount) - refundReceipt!.fee
        );
        await lbcBalanceDiffAfterRefundAssertion();
        await userBalanceDiffAfterRefundAssertion();
      });
    });

    it("refundPegOut with wrong rounding", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts, bridgeMock } = fixtureResult;
      const provider = liquidityProviders[0];
      const user = accounts[0];
      let lbc = fixtureResult.lbc;
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();

      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: 0,
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      quote.deposityAddress = bs58check.decode(
        "2Mxo7RNBLYVxFhiz4MHbr1UyDWgzCReBRBx"
      );
      quote.productFeeAmount = 0;
      quote.value = BigInt("72160329123080000");
      quote.gasFee = BigInt("11290000000000");
      quote.callFee = BigInt("300000000000000");
      const pegoutAmount = totalValue(quote);

      const lpBalanceDiffAfterDepositAssertion =
        await createBalanceDifferenceAssertion({
          source: lbc,
          address: provider.signer.address,
          expectedDiff: 0,
          message: "Incorrect LP balance after deposit",
        });
      const lbcBalanceDiffAfterDepositAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: pegoutAmount,
          message: "Incorrect LBC balance after deposit",
        });
      const userBalanceAfterDepositAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: user.address,
          message: "Incorrect user balance after deposit",
        });

      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });
      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );

      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: pegoutAmount,
      });
      const depositReceipt = await depositTx.wait();
      await lpBalanceDiffAfterDepositAssertion();
      await lbcBalanceDiffAfterDepositAssertion();
      await userBalanceAfterDepositAssertion(
        (pegoutAmount + depositReceipt!.fee) * -1n
      );

      const littleEndianPaidAmount = "a01b6e0000000000";
      const btcTx = `0x0200000001c58d201925a80f49c3160bd97be969453d64c311d7c7a2c2c31318fdeedb8eb7020000006a47304402201944d92c0afd1524ac763c709269f70ca3a7597deffa8d732dad5fb1318ff5bc02205970622ade1d31212ad95ee62926d0acdf7e61e481c118acd02b9c9d29e9913b012102361cffc83b11d361119acd4e57c7103f94bce4ee990e3f2d3fac19017fe076bffdffffff03${littleEndianPaidAmount}17a9143ce07516dd6c85b69b4abec139fbac01cf84fec0870000000000000000226a20${hexlify(
        quoteHash
      ).slice(
        2
      )}ba9db202000000001976a9140147059622479e482bc1bf7f7ca8433bbfc3a34888ac00000000`;
      const lpBalanceAfterRefundAssertion = await createBalanceUpdateAssertion({
        source: ethers.provider,
        address: provider.signer.address,
        message: "Incorrect LP balance after refund",
      });
      const lbcBalanceDiffAfterRefundAssertion =
        await createBalanceDifferenceAssertion({
          source: ethers.provider,
          address: await lbc.getAddress(),
          expectedDiff: pegoutAmount * -1n,
          message: "Incorrect LBC balance after refund",
        });

      lbc = lbc.connect(provider.signer);
      const refundTx = await lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      const refundReceipt = await refundTx.wait();
      await expect(refundTx).to.emit(lbc, "PegOutRefunded").withArgs(quoteHash);
      await expect(refundTx).not.to.emit(lbc, "Penalized");
      await lpBalanceAfterRefundAssertion(pegoutAmount - refundReceipt!.fee);
      await lbcBalanceDiffAfterRefundAssertion();
      // assert that the paid value is truly truncated
      expect(fromLeHex(littleEndianPaidAmount)).to.be.eq(
        weiToSat(quote.value) - 1n
      );
    });

    it("not generate transaction to DAO when product fee is 0 in refundPegOut", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts, bridgeMock } = fixtureResult;
      const provider = liquidityProviders[0];
      const user = accounts[0];
      let lbc = fixtureResult.lbc;
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();

      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });

      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });
      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const btcTx = await generateRawTx(lbc, quote);
      lbc = lbc.connect(provider.signer);
      const assertFeeColectorBalance = await createBalanceDifferenceAssertion({
        source: ethers.provider,
        address: ZERO_ADDRESS,
        expectedDiff: 0,
        message: "Incorrect DAO fee collector balance after refund",
      });
      const refundTx = await lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.emit(lbc, "PegOutRefunded").withArgs(quoteHash);
      await expect(refundTx).not.to.emit(lbc, "DaoFeeSent");
      await assertFeeColectorBalance();
    });

    it("not allow user to re deposit a refunded quote", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts, bridgeMock } = fixtureResult;
      const provider = liquidityProviders[0];
      const user = accounts[0];
      let lbc = fixtureResult.lbc;
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();

      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });

      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });
      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );

      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const btcTx = await generateRawTx(lbc, quote);
      lbc = lbc.connect(provider.signer);
      const refundTx = await lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.emit(lbc, "PegOutRefunded").withArgs(quoteHash);
      await expect(refundTx).not.to.emit(lbc, "Penalized");
      const secondDeposit = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(secondDeposit).to.be.revertedWith("LBC064");
    });

    it("validate that the quote was processed on refundPegOut", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts, lbc } = fixtureResult;
      const provider = liquidityProviders[0];
      const user = accounts[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const refundTx = lbc.refundPegOut(
        quoteHash,
        anyHex,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC042");
    });

    it("revert if LP tries to refund a pegout thats already been refunded by user", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts } = fixtureResult;
      const provider = liquidityProviders[0];
      let lbc = fixtureResult.lbc;
      const user = accounts[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      // so its expired after deposit
      quote.expireDate = Math.round(Date.now() / 1000) + 35;
      quote.expireBlock = await ethers.provider
        .getBlockNumber()
        .then((result) => result + 10);
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);

      lbc = lbc.connect(user);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      // increase 9 blocks and then 1 block that takes 50s to mine to force expiration
      await hardhatHelpers.mine(9);
      await hardhatHelpers.time.increase(50);

      const refundUserTx = await lbc.refundUserPegOut(quoteHash);
      await expect(refundUserTx).to.emit(lbc, "PegOutUserRefunded");
      lbc = lbc.connect(provider.signer);
      const refundTx = lbc.refundPegOut(
        quoteHash,
        anyHex,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC064");
    });

    it("penalize LP if refunds after expiration", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { liquidityProviders, accounts, bridgeMock } = fixtureResult;
      const provider = liquidityProviders[0];
      let lbc = fixtureResult.lbc;
      const user = accounts[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      quote.expireBlock = await ethers.provider
        .getBlockNumber()
        .then((result) => result + 10);
      quote.expireDate = Math.round(Date.now() / 1000) + 100;
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));

      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });

      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      await hardhatHelpers.mine(9);
      await hardhatHelpers.time.increase(200);

      const btcTx = await generateRawTx(lbc, quote);
      lbc = lbc.connect(provider.signer);
      const refundTx = await lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.emit(lbc, "PegOutRefunded").withArgs(quoteHash);
      await expect(refundTx)
        .to.emit(lbc, "Penalized")
        .withArgs(provider.signer.address, quote.penaltyFee, quoteHash);
    });

    it("fail if provider is not registered for pegout on refundPegout", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[1];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();

      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      lbc = lbc.connect(provider.signer);
      const refundTx = lbc.refundPegOut(
        quoteHash,
        anyHex,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC001");
    });

    it("emit event when pegout is deposited", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const pegoutValue = totalValue(quote);
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: pegoutValue,
      });
      const depositTimestamp = await ethers.provider
        .getBlock("latest")
        .then((block) => block!.timestamp);
      await expect(depositTx)
        .to.emit(lbc, "PegOutDeposit")
        .withArgs(quoteHash, user.address, pegoutValue, depositTimestamp);
      // deposit again an expect an error to ensure quote is stored
      const failedTx = lbc.depositPegout(quote, signature, {
        value: pegoutValue,
      });
      await expect(failedTx).to.be.revertedWith("LBC028");
    });

    it("not allow to deposit less than total required on pegout", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const pegoutValue = totalValue(quote);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: pegoutValue - 1n,
      });
      await expect(depositTx).to.be.revertedWith("LBC063");
    });

    it("not allow to deposit pegout if quote expired", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      quote.expireBlock = await ethers.provider
        .getBlockNumber()
        .then((result) => result - 1);
      quote.expireDate = Math.round(Date.now() / 1000) + 100;
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);

      const revertByBlocks = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(revertByBlocks).to.be.revertedWith("LBC047");

      await hardhatHelpers.time.increase(200);
      const revertByTime = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(revertByTime).to.be.revertedWith("LBC046");
    });

    it("not allow to deposit pegout after deposit date limit", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      quote.depositDateLimit = quote.agreementTimestamp;
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.be.revertedWith("LBC065");
    });

    it("not allow to deposit the same quote twice", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders, lbc } = fixtureResult;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);

      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const secondDeposit = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(secondDeposit).to.be.revertedWith("LBC028");
    });

    it("fail to deposit if provider resigned", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(provider.signer);
      await lbc.resign();
      const resignationBlocks = await lbc.getResignDelayBlocks();
      await hardhatHelpers.mine(resignationBlocks);
      lbc = lbc.connect(user);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.be.revertedWith("LBC037");
    });

    it("refund user", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      quote.expireBlock = await ethers.provider
        .getBlockNumber()
        .then((result) => result + 10);
      quote.expireDate = Math.round(Date.now() / 1000) + 100;
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const userBalanceBeforeDepositAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: user.address,
          message: "Incorrect user balance before deposit",
        });
      const depositTx = await lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      const depositReceipt = await depositTx.wait();
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      await userBalanceBeforeDepositAssertion(
        (totalValue(quote) + depositReceipt!.fee) * -1n
      );
      await hardhatHelpers.mine(9);
      await hardhatHelpers.time.increase(200);
      const userBalanceBeforeRefundAssertion =
        await createBalanceUpdateAssertion({
          source: ethers.provider,
          address: user.address,
          message: "Incorrect user balance before deposit",
        });
      const refundTx = await lbc.refundUserPegOut(quoteHash);
      const refundReceipt = await refundTx.wait();
      await expect(refundTx)
        .to.emit(lbc, "PegOutUserRefunded")
        .withArgs(quoteHash, totalValue(quote), user.address);
      await expect(refundTx)
        .to.emit(lbc, "Penalized")
        .withArgs(provider.signer.address, quote.penaltyFee, quoteHash);
      await userBalanceBeforeRefundAssertion(
        totalValue(quote) - refundReceipt!.fee
      );
    });

    it("validate if user had not deposited yet", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders, lbc } = fixtureResult;
      const user = accounts[3];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: liquidityProviders[0].signer,
      });
      quote.expireBlock = 1;
      quote.expireDate = quote.agreementTimestamp;
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const refundTx = lbc.refundUserPegOut(quoteHash);
      await expect(refundTx).to.be.revertedWith("LBC042");
    });

    it("parse raw btc transaction p2pkh script", async () => {
      const btcUtilsAddress = await read()[hre.network.name]["BtcUtils"];
      const BtcUtils = await ethers.getContractAt(
        "BtcUtils",
        btcUtilsAddress.address!
      );
      const firstRawTX =
        "0x0100000001013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40000000006a47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4ffffffff0200879303000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a403938343934346435383039323135366335613139643936356239613735383530326536646263326439353337333135656266343839373336333134656233343700000000";
      const firstTxOutputs = await BtcUtils.getOutputs(firstRawTX);

      const firstNullScript = await BtcUtils.parseNullDataScript(
        firstTxOutputs[1].pkScript
      ).then((result) => Buffer.from(result.slice(2), "hex"));
      const firstDestinationAddress = await BtcUtils.parsePayToPubKeyHash(
        firstTxOutputs[0].pkScript,
        false
      );
      const firstValue = firstTxOutputs[0].value;
      const firstHash = await BtcUtils.hashBtcTx(firstRawTX);

      const secondRawTX =
        "0x01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000";
      const secondTxOutputs = await BtcUtils.getOutputs(secondRawTX);

      const secondNullScript = await BtcUtils.parseNullDataScript(
        secondTxOutputs[1].pkScript
      ).then((result) => Buffer.from(result.slice(2), "hex"));
      const secondDestinationAddress = await BtcUtils.parsePayToPubKeyHash(
        secondTxOutputs[0].pkScript,
        true
      );
      const secondValue = secondTxOutputs[0].value;
      const secondHash = await BtcUtils.hashBtcTx(secondRawTX);

      expect(firstNullScript.at(0)).to.be.eq(64);
      expect(firstNullScript.subarray(1).toString("ascii")).to.be.eq(
        "984944d58092156c5a19d965b9a758502e6dbc2d9537315ebf489736314eb347"
      );
      expect(firstDestinationAddress).to.be.eq(
        hexlify(bs58check.decode("mm2B8EUvZBZUi4BmBwN2M7RwgVBZ6BcVYU"))
      );
      expect(firstValue).to.be.eq("60000000");
      expect(firstHash).to.be.eq(
        "0x03c4522ef958f724a7d2ffef04bd534d9eca74ffc0b28308797d2853bc323ba6"
      );

      expect(secondNullScript.at(0)).to.be.eq(64);
      expect(secondNullScript.subarray(1).toString("ascii")).to.be.eq(
        "e94a89712629bbc9fccd1f0c04a278c0e1052eb7626f93e9a7f1067b406f0576"
      );
      expect(secondDestinationAddress).to.be.eq(
        hexlify(bs58check.decode("16WDqBPwkA8Dvwi9UNPeXCDcpVar7XdD9y"))
      );
      expect(secondValue).to.be.eq("70000000");
      expect(secondHash).to.be.eq(
        "0xfd4251485dafe36aaa6766b38cf236b5925f23f12617daf286e0e92f73708aa3"
      );
    });

    it("fail on refundPegout if btc tx has op return with incorrect quote hash", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders, lbc } = fixtureResult;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);

      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const originalConfirmations = quote.transferConfirmations;
      quote.transferConfirmations = 5; // to generate another hash
      const btcTx = await generateRawTx(lbc, quote);
      quote.transferConfirmations = originalConfirmations;
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      const refundTx = lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC069");
    });

    it("fail on refundPegout if btc tx null data script has wrong format", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.5"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const btcTx = await generateRawTx(lbc, quote);
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      lbc = lbc.connect(provider.signer);
      const incorrectSizeByteTx = btcTx.replace("6a20", "6a40");
      const firstRefundTx = lbc.refundPegOut(
        quoteHash,
        incorrectSizeByteTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(firstRefundTx).to.be.revertedWith("LBC075");

      const incorrectHashSizeTx = btcTx.replace(
        "226a20" + hexlify(quoteHash).slice(2),
        "216a19" + hexlify(quoteHash).slice(2, -2)
      );
      const secondRefundTx = lbc.refundPegOut(
        quoteHash,
        incorrectHashSizeTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(secondRefundTx).to.be.revertedWith("LBC075");
    });

    it("fail on refundPegout if btc tx doesn't have correct amount", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders, bridgeMock } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.3"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );
      const btcTx = await generateRawTx(lbc, quote);
      const incorrectValueTx = btcTx.replace(
        "80c3c90100000000",
        "7fc3c90100000000"
      );
      lbc = lbc.connect(provider.signer);
      const refundTx = lbc.refundPegOut(
        quoteHash,
        incorrectValueTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC067");
    });

    it("fail on refundPegout if btc tx doesn't have correct destination", async () => {
      const fixtureResult = await loadFixture(deployLbcWithProvidersFixture);
      const { accounts, liquidityProviders, bridgeMock } = fixtureResult;
      let lbc = fixtureResult.lbc;
      const user = accounts[3];
      const provider = liquidityProviders[0];
      const quote = getTestPegoutQuote({
        lbcAddress: await lbc.getAddress(),
        value: ethers.parseEther("0.3"),
        refundAddress: user.address,
        liquidityProvider: provider.signer,
        destinationAddressType: "p2pkh",
      });
      const quoteHash = await lbc
        .hashPegoutQuote(quote)
        .then((hash) => getBytes(hash));
      const signature = await provider.signer.signMessage(quoteHash);
      lbc = lbc.connect(user);
      const depositTx = lbc.depositPegout(quote, signature, {
        value: totalValue(quote),
      });
      await expect(depositTx).to.emit(lbc, "PegOutDeposit");
      const { firstConfirmationHeader } = getBtcPaymentBlockHeaders({
        quote: quote,
        firstConfirmationSeconds: 100,
        nConfirmationSeconds: 600,
      });
      const { blockHeaderHash, partialMerkleTree, merkleBranchHashes } =
        getTestMerkleProof();
      await bridgeMock.setHeaderByHash(
        blockHeaderHash,
        firstConfirmationHeader
      );
      const btcTx = await generateRawTx(lbc, quote, "p2sh");
      lbc = lbc.connect(provider.signer);
      const refundTx = lbc.refundPegOut(
        quoteHash,
        btcTx,
        blockHeaderHash,
        partialMerkleTree,
        merkleBranchHashes
      );
      await expect(refundTx).to.be.revertedWith("LBC068");
    });

    it("parse btc raw transaction outputs correctly", async () => {
      const btcUtilsAddress = await read()[hre.network.name]["BtcUtils"];
      const BtcUtils = await ethers.getContractAt(
        "BtcUtils",
        btcUtilsAddress.address!
      );
      const transactions = [
        {
          raw: "0x01000000000101f73a1ea2f2cec2e9bfcac67b277cc9e4559ed41cfc5973c154b7bdcada92e3e90100000000ffffffff029ea8ef00000000001976a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88acb799f60300000000220020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d0400473044022051db70142aac24e8a13050cb0f61183704a7fe572c41a09caf5e7f56b7526f87022017d1a4b068a32af3dcea2d9a0e2f0d648c9f0f7fb01698d83091fd5b57f69ade01473044022028f29f5444ea4be2db3c6895e1414caa5cee9ab79faf1bf9bc12191f421de37102205af1df5158aa9c666f2d8d4d7c9da1ef96d28277f5d4b7c193e93e243a6641ae016952210375e00eb72e29da82b89367947f29ef34afb75e8654f6ea368e0acdfd92976b7c2103a1b26313f430c4b15bb1fdce663207659d8cac749a0e53d70eff01874496feff2103c96d495bfdd5ba4145e3e046fee45e84a8a48ad05bd8dbb395c011a32cf9f88053ae00000000",
          outputs: [
            {
              value: 15706270n,
              pkScript: "0x76a9141770fa9929eee841aee1bfd06f5f0a178ef6ef5d88ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 66492855n,
              pkScript:
                "0x0020701a8d401c84fb13e6baf169d59684e17abd9fa216c8cc5b9fc63d622ff8c58d",
              scriptSize: 34,
              totalSize: 43,
            },
          ],
        },
        {
          raw: "0x010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff1a03583525e70ee95696543f47000000002f4e696365486173682fffffffff03c01c320000000000160014b0262460a83e78d991795007477d51d3998c70629581000000000000160014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b0000000000000000266a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f20120000000000000000000000000000000000000000000000000000000000000000000000000",
          outputs: [
            {
              value: 3284160n,
              pkScript: "0x0014b0262460a83e78d991795007477d51d3998c7062",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 33173n,
              pkScript: "0x0014d729e8dba6f86b5c8d7b3066fd4d7d0e21fd079b",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 0n,
              pkScript:
                "0x6a24aa21a9edf052bd805f949d631a674158664601de99884debada669f237cf00026c88a5f2",
              scriptSize: 38,
              totalSize: 47,
            },
          ],
        },
        {
          raw: "0x0100000000010fe0305a97189636fb57126d2f77a6364a5c6a809908270583438b3622dce6bc050000000000ffffffff6d487f63c4bd89b81388c20aeab8c775883ed56f11f509c248a7f00cdc64ae940000000000ffffffffa3d3d42b99de277265468acca3c081c811a9cc7522827aa95aeb42653c15fc330000000000ffffffffd7818dabb051c4db77da6d49670b0d3f983ba1d561343027870a7f3040af44fe0000000000ffffffff72daa44ef07b8d85e8ef8d9f055e07b5ebb8e1ba6a876e17b285946eb4ea9b9b0000000000ffffffff5264480a215536fd00d229baf1ab8c7c65ce10f37b783ca9700a828c3abc952c0000000000ffffffff712209f13eee0b9f3e6331040abcc09df750e4a287128922426d8d5c78ac9fc50000000000ffffffff21c5cf14014d28ec43a58f06f8e68c52c524a2b47b3be1c5800425e1f35f488d0000000000ffffffff2898464f9eb34f1d77fde2ed75dd9ae9c258f76030bb33be8e171d3e5f3b56390000000000ffffffffd27a5adff11cffc71d88face8f5adc2ce43ad648a997a5d54c06bcdec0e3eb5c0000000000ffffffff5217ca227f0e7f98984f19c59f895a3cfa7b05cb46ed844e2b0a26c9f5168d7a0000000000ffffffff8384e811f57e4515dd79ebfacf3a653200caf77f115bb6d4efe4bc534f0a39dd0000000000ffffffffd0448e1aae0ea56fab1c08dae1bdfe16c46f8ae8cec6042f6525bb7c1da0fa380000000000ffffffff5831c6df8395e3dc315af82c758c622156e2c40d677dececb717f4f20ded28a90000000000ffffffff56c2ffb0554631cff11e3e3fa90e6f35e76f420b29cde1faaa68c07cd0c6f8030100000000ffffffff02881300000000000016001463052ae51729396821a0cd91e0b1e9c61f53e168424e0800000000001600140d76db7b4f8f93a0b445bd782df2182a3e577604024730440220260695f8cf81168b46a24a07c380fd2568ee72f939309ed710e055f146d267db022044813ec9d65a57c8d4298b0bd9600664c3875bd2230b6a376a6fc70577a222bb012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100e0ed473c35a937d0b4d1a5e08f8e61248e80f5fe108c9b8b580792df8675a05d02202073dfd0d44d28780ee321c8a2d18da8157055d37d68793cbe8c53cc1c0a5321012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022034e28210fe7a14dde84cdb9ef4cf0a013bbc027deebcb56232ff2dabb25c12dc02202f4ff4df794ad3dbcfa4d498ec6d0c56b22c027004767851e3b8ffc5652ba529012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302473044022030d5f4ffddf70a6086269ce982bff38c396831d0b5ef5205c3e557059903b2550220575bcf3b233c12b383bf2f16cd52e2fff2c488f0aa29ab3dec22b85b536b1c83012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100cc07265538f0ea4a8b999450549a965b0cc784371cac42cbcf8f49fbabf72b7c02207ef68377d7c6d3817d7c1a7a7936392b7043189ab1aed81eb0a7a3ad424bdcaf012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230248304502210085a8855abe9fd6680cb32911db66914cf970a30f01ecd17c7527fc369bb9f24002206da3457505a514a076954a2e5756fcc14c9e8bdc18301469dfe5b2b6daef723f012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d4e1963f5945dfae7dc73b0af1c65cf9156995a270164c2bcbc4a539130ac268022054464ea620730129ebaf95202f96f0b8be74ff660fcd748b7a107116e01730f3012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402207a5386c7b8bf3cf301fed36e18fe6527d35bc02007afda183e81fc39c1c8193702203207a6aa2223193a5c75ed8df0e046d390dbf862a3d0da1b2d0f300dfd42e8a7012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100c8db534b9ed20ce3a91b01b03e97a8f60853fbc16d19c6b587f92455542bc7c80220061d61d1c49a3f0dedecefaafc51526325bca972e99aaa367f2ebcab95d42395012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100f5287807debe8fc2eeee7adc5b7da8a212166a4580b8fdcf402c049a40b24fb7022006cb422492ba3b1ec257c64e74f3d439c00351f05bc05e88cab5cd9d4a7389b0012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402202edb544a679791424334e3c6a85613482ca3e3d16de0ca0d41c54babada8d4a2022025d0c937221161593bd9858bb3062216a4e55d191a07323104cfef1c7fcf5bc6012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402201a6cf02624884d4a1927cba36b2b9b02e1e6833a823204d8670d71646d2dd2c40220644176e293982f7a4acb25d79feda904a235f9e2664c823277457d33ccbaa6dc012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100d49488c21322cd9a7c235ecddbd375656d98ba1ca06a5284c8c2ffb6bcbba83b02207dab29958d7c1b2466d5b5502b586d7f3d213b501689d42a313de91409179899012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2302483045022100f36565200b245429afb9cdc926510198893e057e5244a7dabd94bedba394789702206786ea4033f5e1212cee9a59fb85e89b6f7fe686ab0a3b8874e77ea735e7c3b5012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d230247304402206ff3703495e0d872cbd1332d20ee39c14de6ed5a14808d80327ceedfda2329e102205da8497cb03776d5df8d67dc16617a6a3904f7abf85684a599ed6c60318aa3be012102b4ee3edac446129ec8c011afaba3e5e1ead0cebfd8545f3f6984c167277f8d2300000000",
          outputs: [
            {
              value: 5000n,
              pkScript: "0x001463052ae51729396821a0cd91e0b1e9c61f53e168",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 544322n,
              pkScript: "0x00140d76db7b4f8f93a0b445bd782df2182a3e577604",
              scriptSize: 22,
              totalSize: 31,
            },
          ],
        },
        {
          raw: "0x01000000010178a1cf4f2f0cb1607da57dcb02835d6aa8ef9f06be3f74cafea54759a029dc000000006a473044022070a22d8b67050bee57564279328a2f7b6e7f80b2eb4ecb684b879ea51d7d7a31022057fb6ece52c23ecf792e7597448c7d480f89b77a8371dca4700a18088f529f6a012103ef81e9c4c38df173e719863177e57c539bdcf97289638ec6831f07813307974cffffffff02801d2c04000000001976a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac0000000000000000426a406539346138393731323632396262633966636364316630633034613237386330653130353265623736323666393365396137663130363762343036663035373600000000",
          outputs: [
            {
              value: 70000000n,
              pkScript: "0x76a9143c5f66fe733e0ad361805b3053f23212e5755c8d88ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 0n,
              pkScript:
                "0x6a4065393461383937313236323962626339666363643166306330346132373863306531303532656237363236663933653961376631303637623430366630353736",
              scriptSize: 66,
              totalSize: 75,
            },
          ],
        },
        {
          raw: "0x020000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff050261020101ffffffff02205fa012000000001976a91493fa9b864d39108a311918320e2a804de2e946f688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000",
          outputs: [
            {
              value: 312500000n,
              pkScript: "0x76a91493fa9b864d39108a311918320e2a804de2e946f688ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 0n,
              pkScript:
                "0x6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9",
              scriptSize: 38,
              totalSize: 47,
            },
          ],
        },
        {
          raw: "0x020000000001010e02566bfc272aed951a7f68152707fd14d29aaf2fe4c8106e623faec848437c0000000000fdffffff02dba01800000000001976a914b2978fcacc03e34dae7b0d9ef112a7b3e5c0bdc488ac03a10185120000001976a9142591f7537994333dc2c119a88defb5b53d34495188ac0247304402205bdb0dfbbeb0ffc7f2d86cd1026a893252f49399d22876dfe6f3ff1ce723507502200f155b8fab03352aec2b07bbd0e0ab147454937f34301518b428af7c6216b79d01210249b9c2a173ec4c9bfae80edf85fa48ff9e196856bf7f48f2208800760bb28d07d4322500",
          outputs: [
            {
              value: 1614043n,
              pkScript: "0x76a914b2978fcacc03e34dae7b0d9ef112a7b3e5c0bdc488ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 79540887811n,
              pkScript: "0x76a9142591f7537994333dc2c119a88defb5b53d34495188ac",
              scriptSize: 25,
              totalSize: 34,
            },
          ],
        },
        {
          raw: "0x010000000001050010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460000000000ffffffff0010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460100000000ffffffff0010b625779e40b4e8d1288e9db32a9a4026f7e98d0ee97a2fd1b43ca8882a460300000000fffffffffd67dda5d256393b6e5b4a1ba117c7b60ebb0ff17ff22d4743f12f3a84bcf84e0100000000fffffffffd67dda5d256393b6e5b4a1ba117c7b60ebb0ff17ff22d4743f12f3a84bcf84e0200000000ffffffff060000000000000000536a4c5063cc1853d0117afb0b709321a29ebd6bff4f0488774c3df3a7eae1f237bce099355a809b79d8e327b4844d4d5b01039c68d000fb57d906712c9403a0561a5cd7175d314dbb75bfa53cd033620f916501a60e000000000000160014f58e1a72b69982143e10e505a61f37aa368d92441302010000000000160014323d105482f5065dcd51f1bc5a213d5d723d58dda6870100000000001600140ccce8622a77f0316227cd311fb233bce31f76f6a68701000000000016001463ac4816199ba682879a2373a16fac78c51f6bdaa687010000000000160014b84a456a5a8af29af60d72b03958a9bebf76e6e502483045022100d1fb958108531911fc0ba7df04267c1842718f1d871c555f8b6ce30cc117d4ca022032099c3918c491d0af7fdded1811e2cd0e86b99458661d97ae87ded3c889382001210257d3f874b8203ed7d4fc254d67f68b67e954c19cd37b1b6a6ce7346a52b437230247304402201cbeb5d7865aa47b6a6692b89fbbcd4caad7047b71db97e42b09149594bb141402207b1eaa83ab4ebcf8b063bc401f892043c8cf346e4993bdfdc9f4f979c27ac8b001210326010652c2334417db10fddc0bb10749a3256555dd22ebe1575da9eb3aeccf530247304402205dbc9abd0df608e9548c8e5b3771f7b1f20ad170951a8c254f620ed989a7ea61022002d00d0739f33eb5afd5d7c5e07891c66939656dd024c6fbde8515d4104c052c0121020802d7c7e0e6f040644950f0712d7225cc4b755ece3e0d61568d6c8e362e375c02483045022100db6c33de82ae9e7abbdcd99265931307716112771d2e4273a7381c63e779a2ae02203376181e7e3474b6e771eea127b9ce943ef1025e9190a75304d9cf94d52ed429012103d1609fe77bb362648e9253ed09b7a560448f93fb0612a74db179ac22cc89e86302483045022100f99a02db4e116b3ff92de3cb0af8e3cf29518695fdfadac6cc9cd2104ae009d402206a1e7060874834a68aa7ad5b2ef19ea29c1f04af61aab28c589dfa8937f2287a012103dbfb01dde37e538772edf37434b4b4268f10ab8ed7e1e6a98f89e50aa1a11f2500000000",
          outputs: [
            {
              value: 0n,
              pkScript:
                "0x6a4c5063cc1853d0117afb0b709321a29ebd6bff4f0488774c3df3a7eae1f237bce099355a809b79d8e327b4844d4d5b01039c68d000fb57d906712c9403a0561a5cd7175d314dbb75bfa53cd033620f916501",
              scriptSize: 83,
              totalSize: 92,
            },
            {
              value: 3750n,
              pkScript: "0x0014f58e1a72b69982143e10e505a61f37aa368d9244",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 66067n,
              pkScript: "0x0014323d105482f5065dcd51f1bc5a213d5d723d58dd",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 100262n,
              pkScript: "0x00140ccce8622a77f0316227cd311fb233bce31f76f6",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 100262n,
              pkScript: "0x001463ac4816199ba682879a2373a16fac78c51f6bda",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 100262n,
              pkScript: "0x0014b84a456a5a8af29af60d72b03958a9bebf76e6e5",
              scriptSize: 22,
              totalSize: 31,
            },
          ],
        },
        {
          raw: "0x010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff1e0367352519444d47426c6f636b636861696ee2fb0ac80e02000000000000ffffffff02e338260000000000160014b23716e183ba0949c55d6cac21a3e94176eed1120000000000000000266a24aa21a9ed561c4fd92722cf983c8c24e78ef35a4634e3013695f09186bc86c6a627f21cfa0120000000000000000000000000000000000000000000000000000000000000000000000000",
          outputs: [
            {
              value: 2504931n,
              pkScript: "0x0014b23716e183ba0949c55d6cac21a3e94176eed112",
              scriptSize: 22,
              totalSize: 31,
            },
            {
              value: 0n,
              pkScript:
                "0x6a24aa21a9ed561c4fd92722cf983c8c24e78ef35a4634e3013695f09186bc86c6a627f21cfa",
              scriptSize: 38,
              totalSize: 47,
            },
          ],
        },
        {
          raw: "0x020000000001016bcabaaf4e28636c4c68252a019268927b79a978cc7a9c2e561d7053dd0bf73b0000000000fdffffff0296561900000000001976a9147aa8184685ca1f06f543b64a502eb3b6135d672088acf9d276e3000000001976a9145ce7908503ef69bfde873fe886133ab8dc23363188ac02473044022078607e1ca987e18ee8934b44ff8a4f0751d27a110540d99deb0a386adbf638c002200a01dc0314bef9b8c966c7a02440309596a6380e1625a7872ed616327a729bed0121029e1bb76f522491f90c542385e6dbff36b92f8984b74f24d0b99b52ea17bed09961352500",
          outputs: [
            {
              value: 1660566n,
              pkScript: "0x76a9147aa8184685ca1f06f543b64a502eb3b6135d672088ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 3816215289n,
              pkScript: "0x76a9145ce7908503ef69bfde873fe886133ab8dc23363188ac",
              scriptSize: 25,
              totalSize: 34,
            },
          ],
        },
        {
          raw: "0x020000000001014aea9ffcf9be9c98a2a3ceb391483328ff406177fdb60047886a50f33569e0540000000000fdffffff02ce095d5a120000001976a914c38cfd37c4b53ebae78de708a3d8438f6e7cc56588acbc622e00000000001976a914c3ea6613a9dcbf0a63863ec3a3b958127d597b4988ac02473044022009351dd62b2494924397a626524a5c08e16d4d214488b847e7a9cd97fa4aac2302200f5a54fff804f19edf316daaea58052a5f0c2ff3de236a45e05a43474e3a6ddf01210258f308ea046d38403d5afb201df933196b7948acead3048a0413bbaacdc42db166352500",
          outputs: [
            {
              value: 78825458126n,
              pkScript: "0x76a914c38cfd37c4b53ebae78de708a3d8438f6e7cc56588ac",
              scriptSize: 25,
              totalSize: 34,
            },
            {
              value: 3039932n,
              pkScript: "0x76a914c3ea6613a9dcbf0a63863ec3a3b958127d597b4988ac",
              scriptSize: 25,
              totalSize: 34,
            },
          ],
        },
        {
          raw: "0x010000000127d57276f1026a95b4af3b03b6aba859a001861682342af19825e8a2408ae008010000008c493046022100cd92b992d4bde3b44471677081c5ece6735d6936480ff74659ac1824d8a1958e022100b08839f167532aea10acecc9d5f7044ddd9793ef2989d090127a6e626dc7c9ce014104cac6999d6c3feaba7cdd6c62bce174339190435cffd15af7cb70c33b82027deba06e6d5441eb401c0f8f92d4ffe6038d283d2b2dd59c4384b66b7b8f038a7cf5ffffffff0200093d0000000000434104636d69f81d685f6f58054e17ac34d16db869bba8b3562aabc38c35b065158d360f087ef7bd8b0bcbd1be9a846a8ed339bf0131cdb354074244b0a9736beeb2b9ac40420f0000000000fdba0f76a9144838a081d73cf134e8ff9cfd4015406c73beceb388acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac00000000",
          outputs: [
            {
              value: 4000000n,
              pkScript:
                "0x4104636d69f81d685f6f58054e17ac34d16db869bba8b3562aabc38c35b065158d360f087ef7bd8b0bcbd1be9a846a8ed339bf0131cdb354074244b0a9736beeb2b9ac",
              scriptSize: 67,
              totalSize: 76,
            },
            {
              value: 1000000n,
              pkScript:
                "0x76a9144838a081d73cf134e8ff9cfd4015406c73beceb388acacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacacac",
              scriptSize: 4026,
              totalSize: 4037,
            },
          ],
        },
      ];

      let outputs;
      for (const tx of transactions) {
        outputs = await BtcUtils.getOutputs(tx.raw);
        expect(outputs.length).to.be.eq(tx.outputs.length);
        for (let i = 0; i < outputs.length; i++) {
          expect(outputs[i].value).to.be.eq(tx.outputs[i].value.toString());
          expect(outputs[i].pkScript).to.be.eq(tx.outputs[i].pkScript);
          expect(outputs[i].scriptSize).to.be.eq(
            tx.outputs[i].scriptSize.toString()
          );
          expect(outputs[i].totalSize).to.be.eq(
            tx.outputs[i].totalSize.toString()
          );
        }
      }
    });
  });
});
