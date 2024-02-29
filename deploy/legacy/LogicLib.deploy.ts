import { ethers } from "hardhat";
import { LedgerSigner } from "@anders-t/ethers-ledger";

async function main() {
    const LogicLib = await ethers.getContractFactory("LogicLib");
    const logicLib = await LogicLib.deploy();
    console.log(logicLib.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
