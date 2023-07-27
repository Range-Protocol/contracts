// returns the sqrt price as a 64x96
import { BigNumber } from "bignumber.js";
import { ethers } from "hardhat";

export const setStorageAt = async (
  address: unknown,
  index: unknown,
  value: unknown
) => {
  await ethers.provider.send("hardhat_setStorageAt", [address, index, value]);
  await ethers.provider.send("evm_mine", []); // Just mines to the next block
};

// eslint-disable-next-line @typescript-eslint/naming-convention
BigNumber.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export const encodePriceSqrt = (reserve1: string, reserve0: string) => {
  return new BigNumber(reserve1)
    .div(reserve0)
    .sqrt()
    .multipliedBy(new BigNumber(2).pow(96))
    .integerValue(3)
    .toString();
};
export const position = (
  address: string,
  lowerTick: number,
  upperTick: number
) => {
  return ethers.utils.solidityKeccak256(
    ["address", "int24", "int24"],
    [address, lowerTick, upperTick]
  );
};

export const getInitializeData = (params: {
  managerAddress: string;
  name: string;
  symbol: string;
}): any =>
  ethers.utils.defaultAbiCoder.encode(
    ["address", "string", "string", "address"],
    [
      params.managerAddress,
      params.name,
      params.symbol,
      "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c",
    ]
  );

export const bn = (value: any) => ethers.BigNumber.from(value);

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
export const parseEther = (value: string) => ethers.utils.parseEther(value);
