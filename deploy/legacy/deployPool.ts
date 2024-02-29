import { ethers } from "hardhat";
import {encodePriceSqrt} from "../../test/common";

async function main() {
    const [user] = await ethers.getSigners();
    const factory = await ethers.getContractAt("IPancakeV3Factory", "0x1F98431c8aD98523631AE4a59f267346ea31F984");
    // const MockERC2O = await ethers.getContractFactory("MockERC20");
    const token0 = await ethers.getContractAt("MockERC20", "0x9b83003F42321c90C8AF6681fC7A3895FD7A112d");
    const token1 = await ethers.getContractAt("MockERC20", "0xb64a7Af1752c91c57DA3F0e2a6D812415ca3DEb7");

    console.log(token0.address);
    console.log(token1.address);

    // const ret = await factory.createPool(token0.address, token1.address, 500);
    const poolAddress = await factory.getPool(token0.address, token1.address, 500);
    console.log(poolAddress)
    const pool = await ethers.getContractAt("IPancakeV3Pool", "0x4bF51b2Fe2275B6b5e1D0D876C1f1FefB6B81D71");
    // await pool.initialize(encodePriceSqrt("1", "1"));
    // await pool.increaseObservationCardinalityNext("15");

    const amount = ethers.utils.parseEther("10");

    const funcMint = new ethers.utils.Interface([
        "function mint(tuple(address, address, uint24, int24, int24, uint256, uint256, uint256, uint256, address, uint256)) external"
    ]);
    let data = funcMint.encodeFunctionData("mint", [[
        token0.address,
        token1.address,
        500,
        -10,
        10,
        amount,
        amount,
        0,
        0,
        user.address,
        new Date().getTime()
    ]])

    const NFPM = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88";
    // await token0.approve(NFPM, amount);
    // await token1.approve(NFPM, amount);
    //
    // await user.sendTransaction({
    //     to: NFPM,
    //     data
    // });
    //
    console.log((await token0.balanceOf(poolAddress)).toString())
    console.log((await token1.balanceOf(poolAddress)).toString())

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
