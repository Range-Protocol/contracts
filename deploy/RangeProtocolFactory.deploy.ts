import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
async function main() {
  const provider = ethers.getDefaultProvider("");
  const ledger = await new LedgerSigner(provider, "");
  const ALGEBRA_FACTORY = "0xC848bc597903B4200b9427a3d7F61e3FF0553913";
  let RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  RangeProtocolFactory = await RangeProtocolFactory.connect(ledger);
  const factory = await RangeProtocolFactory.deploy(ALGEBRA_FACTORY);
  console.log("Factory: ", factory.address);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
