# 🔍 Scan Port

**Scan Port** é um utilitário em **Bash** para escanear portas TCP em redes IPv4 de forma rápida e eficiente.  
Ele suporta **multithreading**, detecta automaticamente faixas de IP, classifica hosts como **OPEN**, **CLOSED** ou **NOT PING**, e oferece modos avançados de exibição dos resultados.

O script **não cria arquivos**, apenas utiliza arquivos temporários durante a execução e imprime tudo diretamente no terminal.

---

## ✨ Recursos

- 🚀 Suporte a multithreading (padrão: **254 threads**)
- 🔍 Teste de portas via **netcat (nc)**
- 📡 Verificação de atividade via **ping**
- 🧭 Detecção automática de máscara e faixa de IP
- ⚙️ Aceita CIDR ou formatos simplificados (`192.168.1`, `10`, etc.)
- 🔒 Proteção que impede scans acidentais em redes muito grandes (com `--force`)

---

## 📥 Instalação

Clone o repositório:

```bash
git clone https://github.com/SEU_USUARIO/scan-port.git
cd scan-port
```

Dê permissão de execução:

```bash
chmod +x scan
```

Opcional: mova para o PATH:

```bash
sudo mv scan /usr/local/bin/
```

---

## 📝 Uso

```
scan [OPÇÕES] <rede> <porta>
```

### Exemplos

```bash
scan 192.168.1.0/24 80
scan 192.168.1 443
scan --open 10.0 22
scan --list 192.168 3389
scan -nt 100 172.16 3306
scan --force 10 80
```

---

## ⚙️ Opções

| Opção | Descrição |
|-------|-----------|
| `-h`, `--help` | Exibe a ajuda |
| `--no-thread` | Executa sequencialmente (equivale a `-nt 1`) |
| `-nt N` | Define o número máximo de threads (padrão: 254) |
| `-o`, `--open` | Exibe somente hosts com porta aberta |
| `-L`, `--list` | Lista todos os hosts com status: OPEN / CLOSED / NOT PING |
| `--force` | Ignora restrição de proteção para redes grandes |

---

## 🧠 Funcionamento Interno

1. Interpreta automaticamente a rede informada:
   - Ex.: 192.168.1.0/24, 192.168.1, 10, etc.
2. Calcula o número de octetos variáveis baseado na máscara.
3. Para cada IP:
   - Testa conectividade via `ping -W1`
   - Testa porta TCP com `nc -z -w1`
4. Classifica em três arquivos temporários:
   - **OPEN** – porta aberta
   - **CLOSED** – porta fechada
   - **NOT PING** – host não responde ICMP
5. Os resultados são exibidos diretamente no terminal.

---

## ⚠️ Avisos

- **Não utilize para escanear redes que você não administra. Pode ser ilegal.**
- Escanear redes muito grandes pode gerar tráfego intenso.
- Dependências necessárias:
  - `bash`, `ping`, `nc`, `xargs` e `seq`

---

## 🧪 Testado em

- Ubuntu 22.04 / 24.04
- Debian 11 / 12  
- Linux Mint  
- Arch Linux  

---

## 📄 Licença

```
MIT License © 2025 IGOR OLIVEIRA
```

---

## 🤝 Contribuições

Pull requests são bem-vindos!  
Sugestões de melhorias, performance ou compatibilidade também são aceitas.

---

## ⭐ Suporte

Se gostou do projeto, deixe uma **estrela ⭐ no GitHub** para apoiar o desenvolvimento!
