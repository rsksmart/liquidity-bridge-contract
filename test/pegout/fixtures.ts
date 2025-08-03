import hre, { upgrades, ethers } from "hardhat";
import {
  PEGOUT_CONSTANTS,
  ProviderType,
  ZERO_ADDRESS,
} from "../utils/constants";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { PegOutContract } from "../../typechain-types";
import { getTestPegoutQuote, totalValue } from "../utils/quotes";
import { getBytes } from "ethers";

// TODO this should be removed once the collateral management has its final implementation and test files, then
// this file should import a function from there
export async function deployCollateralManagement() {
  const CollateralManagement = await ethers.getContractFactory(
    "CollateralManagementContract"
  );
  const FlyoverDiscovery = await ethers.getContractFactory(
    "FlyoverDiscoveryContract"
  );
  const signers = await ethers.getSigners();
  const lastSigner = signers.pop();
  if (!lastSigner) throw new Error("owner can't be undefined");
  const owner = lastSigner;

  const collateralManagement = await upgrades.deployProxy(
    CollateralManagement,
    [owner.address, 500n, ethers.parseEther("0.6"), 500n]
  );

  const discovery = await upgrades.deployProxy(FlyoverDiscovery, [
    owner.address,
    await collateralManagement.getAddress(),
  ]);
  await collateralManagement
    .connect(owner)
    .grantRole(
      await collateralManagement.COLLATERAL_ADDER(),
      await discovery.getAddress()
    );

  const pegInLp = signers.pop();
  const pegOutLp = signers.pop();
  const fullLp = signers.pop();
  if (!pegInLp || !pegOutLp || !fullLp)
    throw new Error("LP can't be undefined");

  await discovery
    .connect(pegInLp)
    .register("Pegin Provider", "lp1.com", true, ProviderType.PegIn, {
      value: ethers.parseEther("0.6"),
    });
  await discovery
    .connect(pegOutLp)
    .register("PegOut Provider", "lp2.com", true, ProviderType.PegOut, {
      value: ethers.parseEther("0.6"),
    });
  await discovery
    .connect(fullLp)
    .register("Full Provider", "lp3.com", true, ProviderType.Both, {
      value: ethers.parseEther("1.2"),
    });

  return {
    collateralManagement,
    discovery,
    signers,
    owner,
    pegInLp,
    pegOutLp,
    fullLp,
  };
}

export async function deployPegOutContractFixture() {
  const deployResult = await deployCollateralManagement();
  const collateralManagement = deployResult.collateralManagement;
  const collateralManagementAddress = await collateralManagement.getAddress();
  const bridgeMock = await ethers.deployContract("BridgeMock");

  const initializationParams: Parameters<PegOutContract["initialize"]> = [
    deployResult.owner.address,
    await bridgeMock.getAddress(),
    PEGOUT_CONSTANTS.TEST_DUST_THRESHOLD,
    collateralManagementAddress,
    false,
    PEGOUT_CONSTANTS.TEST_BTC_BLOCK_TIME,
    0,
    ZERO_ADDRESS,
  ];

  const libraries = await deployLibraries(
    hre.network.name,
    "Quotes",
    "BtcUtils",
    "SignatureValidator"
  );
  const PegOutContract = await ethers.getContractFactory("PegOutContract", {
    libraries: {
      Quotes: libraries.Quotes.address,
      BtcUtils: libraries.BtcUtils.address,
      SignatureValidator: libraries.SignatureValidator.address,
    },
  });

  const contract = await upgrades.deployProxy(
    PegOutContract,
    initializationParams,
    {
      unsafeAllow: ["external-library-linking"],
    }
  );
  await collateralManagement
    .connect(deployResult.owner)
    .grantRole(
      await collateralManagement.COLLATERAL_SLASHER(),
      await contract.getAddress()
    );
  return { contract, bridgeMock, initializationParams, ...deployResult };
}

export async function paidPegOutFixture() {
  const deployResult = await deployPegOutContractFixture();
  const { signers, contract, pegOutLp } = deployResult;
  const user = signers.pop();
  if (!user) throw new Error("user can't be undefined");
  const quote = getTestPegoutQuote({
    lbcAddress: await contract.getAddress(),
    liquidityProvider: pegOutLp,
    refundAddress: user.address,
    value: ethers.parseEther("1.23"),
  });
  const quoteHash = await contract.hashPegOutQuote(quote);
  const signature = await pegOutLp.signMessage(getBytes(quoteHash));
  const depositTx = await contract
    .connect(user)
    .depositPegOut(quote, signature, { value: totalValue(quote) });
  const depositReceipt = await depositTx.wait();

  return { user, quote, quoteHash, depositTx, depositReceipt, ...deployResult };
}
