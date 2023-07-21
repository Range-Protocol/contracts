import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x13abd383558915d498b52C851BC50D7eC2b7DA1b"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x497C7fda22E169b4be2D59E215928806328dEaeE"; // To be updated.
  const vaultImplAddress = "0x780BaAf9E91aFaDA141004ed4515f85d65a36101"; // to be updated.
  const token0 = "0x9b83003F42321c90C8AF6681fC7A3895FD7A112d";
  const token1 = "0xb64a7Af1752c91c57DA3F0e2a6D812415ca3DEb7";
  const fee = 500; // To be updated.
  const name = "Test Token"; // To be updated.
  const symbol = "TT"; // To be updated.

  let factory = await ethers.getContractAt(
    "RangeProtocolFactory",
    rangeProtocolFactoryAddress
  );
  const data = getInitializeData({
    managerAddress,
    name,
    symbol,
  });

  const tx = await factory.createVault(token0, token1, fee, vaultImplAddress, data);
  // console.log((await factory.vaultCount()).toString())
  // const pool = await factory.getVaultAddresses(1, 1);
  // console.log(pool)
  // const txReceipt = await tx.wait();
  // const [
  //   {
  //     args: { vault },
  //   },
  // ] = txReceipt.events.filter(
  //   (event: { event: any }) => event.event === "VaultCreated"
  // );
  // console.log("Vault: ", vault);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
