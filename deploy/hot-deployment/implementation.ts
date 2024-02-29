import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

const configPath = path.join(__dirname, "../config.json");
async function main() {
    const RangeProtocolVault = await ethers.getContractFactory("RangeProtocolVault");
    const vaultImpl = await RangeProtocolVault.deploy();
    console.log("Implementation: ", vaultImpl.address);
    const configData = JSON.parse(fs.readFileSync(configPath));
    configData.implementation = vaultImpl.address;
    fs.writeFileSync(configPath, JSON.stringify(configData));
    console.log("DONE!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
