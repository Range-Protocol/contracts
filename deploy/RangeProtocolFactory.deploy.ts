import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";
async function main() {
  const provider = ethers.getDefaultProvider("");
  const ledger = await new LedgerSigner(provider, "");
  const FUSIONX_V3_FACTORY = "0x530d2766D1988CC1c000C8b7d00334c14B69AD71";
  let RangeProtocolFactory = await ethers.getContractFactory(
    "RangeProtocolFactory"
  );
  RangeProtocolFactory = await RangeProtocolFactory.connect(ledger);
  const factory = await RangeProtocolFactory.deploy(FUSIONX_V3_FACTORY);
  console.log("Factory: ", factory.address);
}
// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
