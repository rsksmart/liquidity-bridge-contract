import hre, { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { getTestPegoutQuote, totalValue } from "./utils/quotes";
import { LP_COLLATERAL } from "./utils/constants";
import { deployContract } from "../scripts/deployment-utils/utils";

describe("LBC signature malleability defense", () => {
  async function deployRealLbc() {
    // Deploy libraries with real SignatureValidator
    const network = hre.network.name;
    const quotesDeployment = await deployContract(
      "contracts/legacy/Quotes.sol:Quotes",
      network
    );
    const btcUtilsDeployment = await deployContract("BtcUtils", network);
    const realSignatureValidatorDeployment = await deployContract(
      "SignatureValidator",
      network
    );
    const bridgeMockDeployment = await deployContract("BridgeMock", network);

    // Deploy LBC with real SignatureValidator
    const LiquidityBridgeContract = await ethers.getContractFactory(
      "LiquidityBridgeContract",
      {
        libraries: {
          Quotes: quotesDeployment.address,
          BtcUtils: btcUtilsDeployment.address,
          SignatureValidator: realSignatureValidatorDeployment.address,
        },
      }
    );

    const lbcProxy = await upgrades.deployProxy(
      LiquidityBridgeContract,
      [
        bridgeMockDeployment.address, // bridgeAddress
        ethers.parseEther("0.03"), // minimumCollateral
        ethers.parseEther("0.5"), // minimumPegIn
        10, // rewardPercentage
        60, // resignDelayBlocks
        2300n * 65164000n, // dustThreshold
        900, // btcBlockTime
        false, // mainnet
      ],
      {
        unsafeAllow: ["external-library-linking"],
      }
    );
    await lbcProxy.waitForDeployment();

    // Upgrade to V2 with real SignatureValidator
    const quotesV2Deployment = await deployContract("QuotesV2", network);
    const LiquidityBridgeContractV2 = await ethers.getContractFactory(
      "LiquidityBridgeContractV2",
      {
        libraries: {
          QuotesV2: quotesV2Deployment.address,
          BtcUtils: btcUtilsDeployment.address,
          SignatureValidator: realSignatureValidatorDeployment.address,
        },
      }
    );

    const lbc = await upgrades.upgradeProxy(
      lbcProxy,
      LiquidityBridgeContractV2,
      {
        unsafeAllow: ["external-library-linking"],
      }
    );
    await lbc.waitForDeployment();

    const accounts = await ethers.getSigners();
    const lp = accounts[1];
    const user = accounts[2];

    // Register one LP with pegout support
    await lbc.connect(lp).register("LP", "http://lp.local", true, "both", {
      value: LP_COLLATERAL,
    });

    return { lbc, lp, user };
  }

  it("reverts with ECDSAInvalidSignatureS when depositPegout gets high-s signature", async () => {
    const { lbc, lp, user } = await loadFixture(deployRealLbc);

    const quote = getTestPegoutQuote({
      lbcAddress: await lbc.getAddress(),
      liquidityProvider: lp,
      refundAddress: user.address,
      value: ethers.parseEther("1"),
    });

    const quoteHash = await lbc.hashPegoutQuote(quote);

    const lowS = await lp.signMessage(ethers.getBytes(quoteHash));
    const parsed = ethers.Signature.from(lowS);

    const secp256k1n =
      0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
    const s = BigInt(parsed.s);
    const sPrime = secp256k1n - s;
    const vPrime = parsed.v === 27 ? 28 : 27;
    const malleableSig = ethers.hexlify(
      ethers.concat([
        ethers.getBytes(parsed.r),
        ethers.getBytes(ethers.toBeHex(sPrime, 32)),
        ethers.getBytes(ethers.toBeHex(vPrime, 1)),
      ])
    );

    const errorHelper = await ethers.deployContract("ECDSAError");
    await errorHelper.waitForDeployment();

    await expect(
      lbc
        .connect(user)
        .depositPegout(quote, malleableSig, { value: totalValue(quote) })
    ).to.be.revertedWithCustomError(errorHelper, "ECDSAInvalidSignatureS");
  });
});
