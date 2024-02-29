import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";

async function main() {
    const provider = ethers.getDefaultProvider(""); // To be updated.
    const ledger = await new LedgerSigner(provider, ""); // To be updated.

    const NativeTokenSupport = (await ethers.getContractFactory("NativeTokenSupport")).connect(ledger);
    const nativeTokenSupport = await NativeTokenSupport.deploy();
    console.log("Native Token Support: ", nativeTokenSupport.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
