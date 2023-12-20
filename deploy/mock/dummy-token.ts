import {ethers} from "hardhat";
import fs from "fs";
import path from "path";

const configPath = path.join(__dirname, "../config.json");
async function main() {
    const configData = JSON.parse(fs.readFileSync(configPath));
    const AMM_FACTORY = configData.ammFactory;
    const MockERC20 = await ethers.getContractFactory(
        "MockERC20"
    );
    const token0 = await MockERC20.deploy();
    const token1 = await MockERC20.deploy();
    configData.token0 = token0.address;
    configData.token1 = token1.address;
    fs.writeFileSync(configPath, JSON.stringify(configData));
    console.log("DONE!");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
