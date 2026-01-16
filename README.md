## Crypto Trading Foundry

Experimental AMM components built with Foundry. Current focus is a minimal token pair contract with tests; upcoming work includes an `AMMRouter.sol` `PairFactory.sol`,and additional pool logic.

### Project status
- ✅ Token pair interface and implementation (`TokenPair.sol`, `ITokenPair.sol`)
- ✅ Foundry test suite with ERC20 mocks
- 🚧 Planned: `AMMRouter.sol``


### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (only needed for tooling in `package.json`; contracts/tests run via Foundry)

### Install & build
```bash
forge install
forge build
```

### Test
```bash
forge test
```

### Format
```bash
forge fmt
```

### Gas snapshots
```bash
forge snapshot
```



### Roadmap (near term)
- Add `AMMRouter.sol` and integration tests.
- Add `PairFactory.sol` and integration tests.

