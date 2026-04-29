import { task, types } from "hardhat/config";
import { readFileSync } from "fs";
import { DeploymentConfig, read } from "../scripts/deployment-utils/deploy";
import {
  ApiPeginQuote,
  ApiPegoutQuote,
  parsePeginQuote,
  parsePegoutQuote,
} from "./utils/quote";

task("hash-quote")
  .setDescription("Prints the hash of the quote provided in the input file")
  .addParam(
    "file",
    "The file containing the quote to hash",
    undefined,
    types.inputFile
  )
  .addParam(
    "type",
    "Wether the quote is a PegIn or PegOut quote",
    undefined,
    types.string
  )
  .setAction(async (args, hre) => {
    const { network, ethers } = hre;
    const typedArgs = args as { file: string; type: string };
    const type: string = typedArgs.type.toLowerCase();
    const inputFile: string = typedArgs.file;

    if (!["pegin", "pegout"].includes(type)) {
      throw new Error("Invalid type. Must be 'pegin' or 'pegout'");
    }
    const fileContent = readFileSync(inputFile);
    const quote: unknown = JSON.parse(fileContent.toString());

    const addresses: Partial<DeploymentConfig> = read();
    const networkDeployments: Partial<DeploymentConfig[string]> | undefined =
      addresses[network.name];
    const lbcAddress = networkDeployments?.LiquidityBridgeContract?.address;
    if (!lbcAddress) {
      throw new Error(
        "LiquidityBridgeContract proxy deployment info not found"
      );
    }
    const lbc = await ethers.getContractAt(
      "LiquidityBridgeContractV2",
      lbcAddress
    );

    if (type === "pegin") {
      const hash = await lbc.hashQuote(parsePeginQuote(quote as ApiPeginQuote));
      console.info(
        `Hash of the provided PegIn quote: \x1b[32m${hash.slice(2)}\x1b[0m`
      );
    } else {
      const hash = await lbc.hashPegoutQuote(
        parsePegoutQuote(quote as ApiPegoutQuote)
      );
      console.info(
        `Hash of the provided PegOut quote: \x1b[32m${hash.slice(2)}\x1b[0m`
      );
    }
  });
