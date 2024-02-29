import { ethers } from "hardhat";
import { getInitializeData } from "../../test/common";

async function main() {
  const managerAddress = "0x84b43ce5fB1FAF013181FEA96ffA4af6179e396a"; // To be updated.
  const rangeProtocolFactoryAddress =
    "0x0165878A594ca255338adfa4d48449f69242Eb8F"; // To be updated.
  const vaultImplAddress = "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853"; // to be updated.
  const token0 = "0x09bc4e0d864854c6afb6eb9a9cdf58ac190d0df9";
  const token1 = "0x78c1b0c915c4faa5fffa6cabf0219da63d7f4cb8";
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

  const tx = await factory.createVault(token0, token1, vaultImplAddress, data);
  const txReceipt = await tx.wait();
  const [
    {
      args: { vault },
    },
  ] = txReceipt.events.filter(
    (event: { event: any }) => event.event === "VaultCreated"
  );
  console.log("Vault: ", vault);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
