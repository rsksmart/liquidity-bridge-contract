import hre, { ethers, upgrades } from "hardhat";
import { deployCollateralManagement } from "../utils/fixtures";
import { PegInContract } from "../../typechain-types";
import { deployLibraries } from "../../scripts/deployment-utils/deploy-libraries";
import { PEGIN_CONSTANTS, ZERO_ADDRESS } from "../utils/constants";

export async function deployPegInContractFixture() {
  const deployResult = await deployCollateralManagement();
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
    PEGIN_CONSTANTS.TEST_REWARD_PERCENTAGE,
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
  await collateralManagement
    .connect(deployResult.owner)
    .grantRole(
      await collateralManagement.COLLATERAL_SLASHER(),
      await contract.getAddress()
    );
  return { contract, bridgeMock, initializationParams, ...deployResult };
}
