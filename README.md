# JURY (JURY)

A fixed-supply ERC-20 token for launch on Robinhood Chain (chain id 4663) through IMD's
ProjectFactory as a custom token launch.

| Parameter | Value |
| --- | --- |
| Solidity contract (manifest `token.contract`) | `JuryToken` |
| `name()` | `JURY` |
| `symbol()` | `JURY` |
| `decimals()` | `18` |
| Total supply | 1,000,000,000 JURY = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Owner / admin | none |
| Mint after construction | impossible (no mint function) |
| Burn | none |
| Transfer fee / tax | none |
| Pause / blocklist / freeze | none |

## Layout

```
foundry.toml                     compiler pins (solc 0.8.26, bytecode_hash = "none")
remappings.txt                   forge-std and @openzeppelin/contracts remappings
src/JuryToken.sol                the token
script/DeployJuryToken.s.sol     local rehearsal deployment (not used by the launch)
test/JuryToken.t.sol             behaviour, failure and fuzz tests
test/DeployJuryToken.t.sol       the script's deploy function, called directly
lib/forge-std                    vendored forge-std v1.9.7 (plain files, no submodule)
lib/openzeppelin-contracts       vendored subset of OpenZeppelin Contracts v5.1.0
```

Only the files `ERC20.sol` depends on are vendored from OpenZeppelin: `ERC20.sol`, `IERC20.sol`,
`extensions/IERC20Metadata.sol`, `utils/Context.sol` and `interfaces/draft-IERC6093.sol`, with the
MIT licence. forge-std is vendored whole, under its MIT/Apache licences.

## Behaviour

`JuryToken` inherits OpenZeppelin's `ERC20` unchanged. Its constructor takes no arguments and
mints `TOTAL_SUPPLY` (1,000,000,000 × 10^18) once to `msg.sender`. That is the only mint that can
ever happen: the contract exposes no `mint`, `burn`, `pause`, blocklist, owner or upgrade entry
point, holds no ether (it has no `receive` or `fallback`), and contains no `DELEGATECALL`,
`CALLCODE` or `SELFDESTRUCT`. Every public function is the standard ERC-20 surface plus the
public constants `TOKEN_NAME`, `TOKEN_SYMBOL`, `TOKEN_DECIMALS` and `TOTAL_SUPPLY`.

Transfers are plain: no fee, no reflection, no exemption list is needed because nothing is
taxed. The launch flows (factory to MerkleDistributor, factory seeding the Uniswap v4 pool,
distributor claims, trader swaps) move exactly the amounts they say.

## Assumptions

- **The deployer is the factory.** On the launch, IMD's ProjectFactory is `msg.sender` of the
  constructor and receives the whole supply. The factory then forwards 10% to the launch's
  MerkleDistributor, seeds the pool with the requester's `poolBps` (88%) and sends the rest (2%)
  to `economics.remainderTo`. The token has no part in that allocation and does not know about it.
- **The supply is final.** `totalSupply()` equals `TOTAL_SUPPLY` forever. No burn is provided, so
  it cannot shrink either.
- **No admin.** There is no owner to set, transfer or renounce. The launch's owner check has
  nothing to inspect on this contract.
- **Solidity name versus token name.** The manifest records the contract as `JuryToken` (9
  characters, within the 32-character limit). The token name and symbol are both `JURY`.

## Deployment parameters

The launch manifest step writes `launch.json` after this work is accepted; it is not part of this
repository. The values it will carry, from the job, are:

| Field | Value |
| --- | --- |
| `token.contract` | `JuryToken` |
| `token.name` / `token.symbol` | `JURY` / `JURY` |
| `token.decimals` | `18` |
| `token.constructorArgs` | `[]` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `contracts` | `[]` (no application contracts) |
| `pool.pairedCurrency` | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` (IMD) |
| `pool.fee` / `pool.tickSpacing` | `12500` / `60` |
| `pool.initialPrice` | `79228162514264337593543950336` (provenance only; the deployer derives the opening price) |
| `economics` | `{"poolBps":8800,"initialMarketCapWei":"2500000000000000000000","remainderTo":"0xeeaf04a41ac45a605e30dc6a41a44e6f75ddf8b6"}` |

Build settings that affect the bytecode the launch hashes: `solc = "0.8.26"`, `optimizer = true`,
`optimizer_runs = 200`, `evm_version = "cancun"`, `bytecode_hash = "none"`. The runtime is about
3 KB, well inside EIP-170.

### Local rehearsal

```
forge script script/DeployJuryToken.s.sol --rpc-url <local node> --broadcast --sender <account>
```

The script reads no environment variables. The broadcasting account becomes the supply holder.
Do not use it for the production launch: that is done by IMD's deployer through the factory.

## After launch

Nothing. The token has no owner-settable configuration, so there is no setter to call and no
value to obtain. Operational responsibilities after launch are:

- **The factory / launch step**, not the token, distributes the supply (swarm share, pool seed,
  remainder). Anyone verifying the launch should check those three transfers on chain.
- **Holders** are responsible for their own keys and approvals; the token cannot recover tokens
  sent to a wrong address, to the token contract itself, or to the zero address (the last is
  rejected, the first two are not recoverable).
- **Explorer verification** of the source is the deployer's step; this repository's
  `foundry.toml` is the configuration to verify against.

## Checks

```
forge build
forge test
forge fmt --check
```

Run the fuzz tests with the verifier's seed to reproduce its run exactly:

```
FOUNDRY_FUZZ_SEED=0xd4ed969556a22454698056b6f2a6e346f8c7aba38530dc7fdb721c224059bf17 forge test
```

The tests read no environment variables and pass in any order and in parallel. They cover:
metadata; the single constructor mint to the deployer (EOA and contract deployer) with its
`Transfer` event; transfer success, zero-amount, self-transfer and whole-balance cases; transfer
failures (insufficient balance, zero receiver); approve and transferFrom success, allowance
accounting, infinite allowance, and failures (beyond allowance, no allowance, zero spender,
insufficient balance); the absence of any mint or admin entry point from both a stranger and the
deployer; that the deployer cannot move a holder's balance; that ether is rejected; that the
runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`; and fuzzed supply conservation.

Passing tests are not a security audit. The contract is OpenZeppelin's audited `ERC20` with a
fixed mint and nothing else, which keeps the independent review small, but that review is still
the launch's final step.
