import { CollateralManagementContract } from "../../typechain-types";
import { COLLATERAL_CONSTANTS } from "../utils/constants";
import { ethers, upgrades } from "hardhat";

export async function deployCollateralManagement() {
  const CollateralManagement = await ethers.getContractFactory(
    "CollateralManagementContract"
  );
  const signers = await ethers.getSigners();
  const lastSigner = signers.pop();
  if (!lastSigner) throw new Error("owner can't be undefined");
  const owner = lastSigner;

  const collateralManagementParams: Parameters<
    CollateralManagementContract["initialize"]
  > = [
    owner.address,
    COLLATERAL_CONSTANTS.TEST_DEFAULT_ADMIN_DELAY,
    COLLATERAL_CONSTANTS.TEST_MIN_COLLATERAL,
    COLLATERAL_CONSTANTS.TEST_RESIGN_DELAY_BLOCKS,
    COLLATERAL_CONSTANTS.TEST_REWARD_PERCENTAGE,
  ];

  const collateralManagement = await upgrades.deployProxy(
    CollateralManagement,
    collateralManagementParams
  );

  return {
    collateralManagement,
    signers,
    owner,
    collateralManagementParams,
  };
}

export async function deployCollateralManagementWithRoles() {
  const deployResult = await deployCollateralManagement();
  const signers = deployResult.signers;
  const adder = signers.pop();
  const slasher = signers.pop();
  if (!adder || !slasher)
    throw new Error("adder and slasher can't be undefined");
  const { collateralManagement, owner } = deployResult;
  await collateralManagement
    .connect(owner)
    .grantRole(await collateralManagement.COLLATERAL_ADDER(), adder.address);
  await collateralManagement
    .connect(owner)
    .grantRole(
      await collateralManagement.COLLATERAL_SLASHER(),
      slasher.address
    );

  return { adder, slasher, ...deployResult };
}

export async function deployCollateralManagementWithProviders() {
  const deployResult = await deployCollateralManagementWithRoles();
  const signers = deployResult.signers;
  const pegInLp = signers.pop();
  const pegOutLp = signers.pop();
  const fullLp = signers.pop();
  if (!pegInLp || !pegOutLp || !fullLp)
    throw new Error("All providers should be defined");
  const { collateralManagement, adder } = deployResult;
  const BASE_COLLATERAL_TX = { value: ethers.parseEther("10") };
  await collateralManagement
    .connect(adder)
    .addPegInCollateralTo(pegInLp.address, BASE_COLLATERAL_TX);
  await collateralManagement
    .connect(adder)
    .addPegOutCollateralTo(pegOutLp.address, BASE_COLLATERAL_TX);
  await collateralManagement
    .connect(adder)
    .addPegInCollateralTo(fullLp.address, BASE_COLLATERAL_TX);
  await collateralManagement
    .connect(adder)
    .addPegOutCollateralTo(fullLp.address, BASE_COLLATERAL_TX);
  const providers = [
    { signer: pegInLp, pegIn: true, pegOut: false },
    { signer: pegOutLp, pegIn: false, pegOut: true },
    { signer: fullLp, pegIn: true, pegOut: true },
  ];
  return { providers, pegInLp, pegOutLp, fullLp, ...deployResult };
}
