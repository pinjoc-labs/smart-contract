# 🚀 PINJOC Protocol

## 📜 Description

PINJOC is a decentralized fixed-rate lending protocol that revolutionizes DeFi lending by implementing a market-driven interest rate mechanism. Built on monad network, the protocol leverages CLOB (Central Limit Order Book) technology using our own Pinjoc CLOB to ensure efficient price discovery and optimal interest rate determination based on real-time supply and demand dynamics.

---

## ❌ Problems

- 🔄 **Variable Interest Rates**: Unpredictable returns & costs
- 📅 **No Fixed Loan Terms**: Open-ended, no set maturity
- 📊 **Utilization-Based Rates**: Interest rates based on utilization rate
- 🏦 **TradFi Relies on Fixed Rates**: Trustable rate by TradFi

---

## ✅ Solutions

- 📈 **CLOB Matching**: Pinjoc CLOB monad the fastest chain
- 🔒 **Fixed Rate, Fixed Term**: Lock interest rate and maturity date
- 📉 **Market-Based Rates**: Interest rates based on supply and demand
- 🔄 **Auto-Roll Supply**: Automated re-lend funds into a new loan
- 🎫 **Tokenized Bond**: Tokenized loans, tradable before maturity

---

## 🏗 Technical Stack

### 🔧 Core Technology
- 📝 **Language**: Solidity ^0.8.19
- 🏗 **Framework**: Foundry
- ⛓ **Blockchain**: Ethereum & monad Network
- 💱 **CLOB Integration**: Pinjoc CLOB System

### 🛠 Development Tools
- 🧪 **Testing**: Forge (Foundry's testing framework)
- 🚀 **Deployment**: Foundry Cast
- 🔗 **Local Network**: Anvil
- 🧐 **Code Analysis**: Forge fmt & snapshot

### 🌐 Networks
- 🛠 **Testnet**: Monad Testnet
- 🌍 **Mainnet**: Ethereum (Planned)

### 📦 Dependencies
- OpenZeppelin Contracts ^4.8.0
- Foundry Toolchain v0.2.0

---

## 🔍 Technical Highlights

### 📑 On-Chain Order Book
- ⚡ Pinjoc CLOB order book system for loan matching
- 🚀 Deployed on Monad Network 
- 💰 Low-cost transactions and settlement
- 📊 Real-time interest rate price discovery

### 🏛 Smart Contract Architecture
- 🏦 Secure lending pool management
- 🎟 Tokenized bond issuance system
- 🛡 Collateral tracking and management
- 📈 Fixed-interest rate based on supply and demand

### 🔥 Auto Liquidation System
- 📡 Real-time health factor monitoring
- 🛑 Automated collateral liquidation
- 🏷 Price oracle integration
- 📉 Safety margin calculations

### 🔍 Smart Contract Addresses
You can check or access the smart contracts on [Monad Testnet Explorer](https://testnet.monadexplorer.com/):

- 🪙 **USDC**: [`0x794Bc7Bcb31F39009827Db1e230fDBEa99830F25`](https://testnet.monadexplorer.com/address/0x794Bc7Bcb31F39009827Db1e230fDBEa99830F25)
- ⚡ **WETH**: [`0x4c1D0b1611155Cc477024C4bbaaD473859c6CD40`](https://testnet.monadexplorer.com/address/0x4c1D0b1611155Cc477024C4bbaaD473859c6CD40)
- 💰 **WBTC**: [`0x9c0E6Bb26f03E980A0C3B2Ab25fb99B7C75a6957`](https://testnet.monadexplorer.com/address/0x9c0E6Bb26f03E980A0C3B2Ab25fb99B7C75a6957)
- 🌊 **WSOL**: [`0x1C55018d65143E9F55ea68021687DEDe068d7F4e`](https://testnet.monadexplorer.com/address/0x1C55018d65143E9F55ea68021687DEDe068d7F4e)
- 🔗 **WLINK**: [`0xfb24385adaa92B68DcdA5163a3Ba3Cd98BD898CE`](https://testnet.monadexplorer.com/address/0xfb24385adaa92B68DcdA5163a3Ba3Cd98BD898CE)
- 🔵 **WAAVE**: [`0xE96D7715CEbe80849b9Ebd6a58172c365Bf8Ebe3`](https://testnet.monadexplorer.com/address/0xE96D7715CEbe80849b9Ebd6a58172c365Bf8Ebe3)
- 📜 **LENDING_CLOB_MANAGER**: [`0xaB614229Bc3f24ccc3D5e2C5dfB49fd5EfF4b5bE`](https://testnet.monadexplorer.com/address/0xaB614229Bc3f24ccc3D5e2C5dfB49fd5EfF4b5bE)
- 🏦 **LENDING_POOL_MANAGER**: [`0x063Deb511f03bcFEB52bbE8cD02EFe83e99B2c6B`](https://testnet.monadexplorer.com/address/0x063Deb511f03bcFEB52bbE8cD02EFe83e99B2c6B)
- 🔄 **PINJOC_ROUTER**: [`0xDf7dC6ca55ab4FcBFd8bea12d44f6CCB1A87C1Cb`](https://testnet.monadexplorer.com/address/0xDf7dC6ca55ab4FcBFd8bea12d44f6CCB1A87C1Cb)

---

## 🚀 Getting Started

### 📌 Prerequisites
- 🖥 **Git**
- 🏗 **Foundry**

### 📥 Installation

1. Clone the repository
```bash
git clone https://github.com/pinjoc-labs/smart-contract
cd smart-contract
```

2. Install dependencies
```bash
forge install
```

3. Build the project
```bash
forge build
```

4. Run tests
```bash
forge test
```

---

## 🛠 Local Development

1. Start local node
```bash
anvil
```

2. Deploy contracts
```bash
forge script script/Deploy.s.sol --rpc-url localhost --broadcast
```

---

## 🌍 Deployment

1. Create .env file
```bash
cp .env.example .env
```

2. Set your environment variables in .env
```ini
PRIVATE_KEY=your_private_key
MONAD_RPC_URL=your_monad_rpc_url
```

3. Deploy to MONAD testnet
```bash
forge script script/Deploy.s.sol --rpc-url https://testnet-rpc.monad.xyz --broadcast --private-key $PRIVATE_KEY --verify --verifier sourcify --verifier-url https://sourcify-api-monad.blockvision.org
```

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---
