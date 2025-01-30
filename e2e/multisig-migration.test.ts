import { ethers } from "hardhat";
import * as helpers from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { changeMultisigOwner } from "../scripts/deployment-utils/change-multisig-owner";
import { expect } from "chai";

describe("Should change LBC owner to the multisig", function () {
  it("Should change the owner", async () => {
    await checkForkedNetwork();

    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      "0xc2A630c053D12D63d32b025082f6Ba268db18300"
    );

    const safeAddress = "0x14842613f48485e0cb68ca88fd24363d57f34541";

    const lbcOwner = await lbc.owner();
    console.info("LBC owner:", lbcOwner);
    await helpers.impersonateAccount(lbcOwner);
    const impersonatedSigner = await ethers.getSigner(lbcOwner);

    await expect(
      changeMultisigOwner(safeAddress, "rskTestnet", impersonatedSigner)
    ).to.not.be.reverted;
    const newLbcOwner = await lbc.owner();
    console.info("New LBC owner:", newLbcOwner);
  });
});

async function checkForkedNetwork() {
  try {
    await ethers.provider.send("evm_snapshot", []);
  } catch (error) {
    console.error("Not a forked network:", error);
  }
}
