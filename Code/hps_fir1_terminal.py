#!/usr/bin/env python3
"""
hps_fir1_terminal_debug.py

Terminal simples para testar 1 FIR reconfiguravel pelo HPS.
Compatível com o simple_cmd_storage_fir1.sv de 1 FIR:

  IN_A       offset 0x00  payload/dado
  IN_B       offset 0x08  comando = (seq << 8) | opcode
  OUT_EXPORT offset 0x10  {last_output, last_input, result_counter16, sample_counter16}
  OUT_DATA   offset 0x18  {command_counter, last_opcode, coeff_count, status_flags, sample_counter[27:0]}

Comandos principais no terminal:
  status
  raw
  cmd 0x20 0x0000000000010000
  coeffs 0 1 1
  coeff_pkl sbmicro/fir/coeffs_2000.pkl 2000
  sample 1000
  filter entrada.pkl saida.pkl accel_1
  q
"""

import os
import mmap
import struct
import time
import re
from pathlib import Path

import pandas as pd

# ============================================================
# Enderecos da bridge
# Ajuste BRIDGE se seu Platform Designer usar outra base.
# ============================================================
BRIDGE = int(os.environ.get("FIR_BRIDGE", "0xC0000000"), 0)
BRIDGE_SPAN = int(os.environ.get("FIR_BRIDGE_SPAN", "0x100"), 0)

IN_A       = 0x00
IN_B       = 0x08
OUT_EXPORT = 0x10
OUT_DATA   = 0x18

# ============================================================
# Opcodes do simple_cmd_storage_fir1.sv
# ============================================================
CMD_NOP           = 0x00
CMD_SET_COEFF     = 0x20
CMD_CLEAR_PENDING = 0x22
CMD_CLEAR_OVERRUN = 0x23
CMD_SET_SAMPLE    = 0x40
CMD_CLEAR_RESULT  = 0x41

DATA_WIDTH = 16
COEFF_WIDTH = 16


# ============================================================
# Acesso basico
# ============================================================
def write_u64(mm, offset, value):
    mm[offset:offset + 8] = struct.pack("<Q", int(value) & 0xFFFFFFFFFFFFFFFF)
    # Em /dev/mem normalmente a escrita ja acontece. O flush pode falhar
    # dependendo do kernel/driver, por isso fica protegido.
    try:
        mm.flush()
    except Exception:
        pass


def read_u64(mm, offset):
    return struct.unpack("<Q", mm[offset:offset + 8])[0]


def parse_int_auto(x):
    return int(str(x), 0)


def to_signed(x, bits):
    x = int(x) & ((1 << bits) - 1)
    if x & (1 << (bits - 1)):
        return x - (1 << bits)
    return x


def sat_s16(x):
    x = int(x)
    if x > 32767:
        return 32767
    if x < -32768:
        return -32768
    return x


def pack4_signed16(c0, c1, c2, c3):
    """
    Empacota 4 coeficientes signed 16 bits em 64 bits.

    in_a[15:0]   = c0
    in_a[31:16]  = c1
    in_a[47:32]  = c2
    in_a[63:48]  = c3
    """
    vals = [c0, c1, c2, c3]
    payload = 0
    for i, c in enumerate(vals):
        payload |= (int(c) & 0xFFFF) << (16 * i)
    return payload & 0xFFFFFFFFFFFFFFFF


# ============================================================
# Decode do simple_cmd_storage_fir1.sv
# ============================================================
def unpack_out_data(raw):
    raw &= 0xFFFFFFFFFFFFFFFF

    command_counter = (raw >> 56) & 0xFF
    last_opcode     = (raw >> 48) & 0xFF
    coeff_count     = (raw >> 36) & 0xFFF
    status_flags    = (raw >> 28) & 0xFF
    sample_counter  = raw & 0x0FFFFFFF

    return {
        "raw_data": raw,
        "command_counter": command_counter,
        "last_opcode": last_opcode,
        "coeff_count": coeff_count,
        "status_flags": status_flags,
        "sample_counter": sample_counter,

        "fir_ready":           (status_flags >> 0) & 1,
        "coeff_pending":       (status_flags >> 1) & 1,
        "sample_pending":      (status_flags >> 2) & 1,
        "coeff_overrun":       (status_flags >> 3) & 1,
        "sample_overrun":      (status_flags >> 4) & 1,
        "coeff_ok":            (status_flags >> 5) & 1,
        "result_valid":        (status_flags >> 6) & 1,
        "fir_en_last":         (status_flags >> 7) & 1,
    }


def unpack_out_export(raw):
    raw &= 0xFFFFFFFFFFFFFFFF
    last_output_u16 = (raw >> 48) & 0xFFFF
    last_input_u16  = (raw >> 32) & 0xFFFF
    result_counter16 = (raw >> 16) & 0xFFFF
    sample_counter16 = raw & 0xFFFF

    return {
        "raw_export": raw,
        "last_output": to_signed(last_output_u16, 16),
        "last_input": to_signed(last_input_u16, 16),
        "result_counter16": result_counter16,
        "sample_counter16": sample_counter16,
    }


# ============================================================
# Leitura de coeficientes/amostras
# ============================================================
def normalize_int_list(values):
    out = []
    for x in values:
        try:
            if pd.isna(x):
                continue
        except Exception:
            pass
        out.append(int(x))
    return out


def read_coeffs_txt(filename):
    text = Path(filename).read_text(encoding="utf-8", errors="ignore")
    lines = []
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        lines.append(line)
    tokens = re.split(r"[,;\s]+", "\n".join(lines).strip())
    tokens = [t for t in tokens if t]
    return [parse_int_auto(t) for t in tokens]


def read_coeffs_csv(filename, column=None):
    path = Path(filename)
    try:
        df = pd.read_csv(path)
    except Exception:
        df = pd.read_csv(path, header=None)

    if column is not None:
        if column not in df.columns:
            raise ValueError(f"Coluna '{column}' nao encontrada no CSV.")
        return normalize_int_list(df[column].tolist())

    for name in ("coeff", "coef", "h", "fir"):
        if name in df.columns:
            return normalize_int_list(df[name].tolist())

    numeric_cols = df.select_dtypes(include="number").columns
    if len(numeric_cols) > 0:
        return normalize_int_list(df[numeric_cols[0]].tolist())

    df = pd.read_csv(path, header=None)
    return normalize_int_list(df.iloc[:, 0].tolist())


def extract_coeffs_from_pkl_object(obj, key=None):
    """
    Aceita:
      - lista/array: [c0, c1, c2, ...]
      - dict: {'coeff': [...]} ou {'wf': [...]} ou {'ws': [...]}
      - DataFrame: coluna key, coeff, wf, ws ou primeira coluna numerica
    """
    if hasattr(obj, "tolist") and not isinstance(obj, pd.DataFrame):
        obj = obj.tolist()

    if isinstance(obj, dict):
        if key is not None and key in obj:
            return normalize_int_list(obj[key])
        for k in ("coeff", "coef", "h", "fir", "wf", "ws"):
            if k in obj:
                return normalize_int_list(obj[k])
        raise ValueError("PKL dict precisa ter chave 'coeff', 'wf', 'ws' ou informe uma chave.")

    if isinstance(obj, pd.DataFrame):
        if key is not None and key in obj.columns:
            return normalize_int_list(obj[key].tolist())
        for k in ("coeff", "coef", "h", "fir", "wf", "ws"):
            if k in obj.columns:
                return normalize_int_list(obj[k].tolist())
        numeric_cols = obj.select_dtypes(include="number").columns
        if len(numeric_cols) == 0:
            raise ValueError("DataFrame do PKL nao tem coluna numerica.")
        return normalize_int_list(obj[numeric_cols[0]].tolist())

    if isinstance(obj, (list, tuple)):
        return normalize_int_list(obj)

    raise ValueError("Formato de PKL nao reconhecido.")


def read_coeffs_file(filename, key=None, column=None):
    suffix = Path(filename).suffix.lower()
    if suffix == ".pkl":
        return extract_coeffs_from_pkl_object(pd.read_pickle(filename), key=key)
    if suffix == ".txt":
        return read_coeffs_txt(filename)
    if suffix == ".csv":
        return read_coeffs_csv(filename, column=column)
    raise ValueError("Formato nao suportado. Use .pkl, .txt ou .csv.")


def read_samples_from_file(filename, column=None):
    path = Path(filename)
    suffix = path.suffix.lower()

    if suffix == ".pkl":
        obj = pd.read_pickle(path)
        if isinstance(obj, pd.DataFrame):
            df = obj
        elif isinstance(obj, dict):
            if column is not None and column in obj:
                return normalize_int_list(obj[column])
            for k in ("x", "sample", "samples", "accel_1", "accel"):
                if k in obj:
                    return normalize_int_list(obj[k])
            raise ValueError("Dict PKL de amostras nao tem coluna/chave conhecida.")
        else:
            if hasattr(obj, "tolist"):
                obj = obj.tolist()
            return normalize_int_list(obj)

    elif suffix == ".csv":
        df = pd.read_csv(path)
    else:
        return read_coeffs_txt(path)

    if column is not None:
        if column not in df.columns:
            raise ValueError(f"Coluna '{column}' nao encontrada.")
        return normalize_int_list(df[column].tolist())

    for k in ("x", "sample", "samples", "accel_1", "accel"):
        if k in df.columns:
            return normalize_int_list(df[k].tolist())

    numeric_cols = df.select_dtypes(include="number").columns
    if len(numeric_cols) == 0:
        raise ValueError("Arquivo de amostras nao tem coluna numerica.")
    return normalize_int_list(df[numeric_cols[0]].tolist())


# ============================================================
# Terminal principal
# ============================================================
class FirTerminal:
    def __init__(self, mm):
        self.mm = mm
        self.seq = 0

    def raw_data(self):
        return read_u64(self.mm, OUT_DATA)

    def raw_export(self):
        return read_u64(self.mm, OUT_EXPORT)

    def status_dict(self):
        st = unpack_out_data(self.raw_data())
        ex = unpack_out_export(self.raw_export())
        st.update(ex)
        return st

    def status(self):
        st = self.status_dict()
        print(f"OUT_DATA   = 0x{st['raw_data']:016X}")
        print(f"OUT_EXPORT = 0x{st['raw_export']:016X}")
        print("")
        print(f"last_opcode       = 0x{st['last_opcode']:02X}")
        print(f"command_counter   = {st['command_counter']}")
        print(f"coeff_count       = {st['coeff_count']}")
        print(f"sample_counter    = {st['sample_counter']}")
        print(f"result_counter16  = {st['result_counter16']}")
        print("")
        print(f"fir_ready         = {st['fir_ready']}")
        print(f"coeff_ok          = {st['coeff_ok']}")
        print(f"result_valid      = {st['result_valid']}")
        print(f"fir_en_last       = {st['fir_en_last']}")
        print("")
        print(f"coeff_pending     = {st['coeff_pending']}")
        print(f"sample_pending    = {st['sample_pending']}")
        print(f"coeff_overrun     = {st['coeff_overrun']}")
        print(f"sample_overrun    = {st['sample_overrun']}")
        print("")
        print(f"last_input        = {st['last_input']}")
        print(f"last_output       = {st['last_output']}")
        return st

    def send_cmd(self, opcode, data=0, delay_s=0.002, verbose=False):
        """
        Escreve exatamente no formato usado no projeto de referencia:
          IN_A = payload
          IN_B = (seq << 8) | opcode
        """
        self.seq = (self.seq + 1) & ((1 << 56) - 1)
        cmd_word = (self.seq << 8) | (int(opcode) & 0xFF)

        write_u64(self.mm, IN_A, int(data))
        # pequena pausa para garantir que o payload ja chegou antes do comando
        if delay_s > 0:
            time.sleep(delay_s)
        write_u64(self.mm, IN_B, cmd_word)
        if delay_s > 0:
            time.sleep(delay_s)

        if verbose:
            print(f"WRITE IN_A=0x{int(data) & 0xFFFFFFFFFFFFFFFF:016X}")
            print(f"WRITE IN_B=0x{cmd_word:016X}  seq={self.seq} opcode=0x{opcode & 0xFF:02X}")
        return cmd_word

    def clear(self):
        self.send_cmd(CMD_CLEAR_PENDING, 0)
        self.send_cmd(CMD_CLEAR_OVERRUN, 0)
        self.send_cmd(CMD_CLEAR_RESULT, 0)
        print("Pending, overrun e result_valid limpos.")

    def wait_command_seen(self, opcode, old_counter=None, timeout_s=0.2):
        t0 = time.perf_counter()
        while time.perf_counter() - t0 < timeout_s:
            st = self.status_dict()
            counter_ok = True if old_counter is None else (st["command_counter"] != old_counter)
            if st["last_opcode"] == (opcode & 0xFF) and counter_ok:
                return True
            time.sleep(0.001)
        return False

    def send_coeff_block(self, c0, c1, c2, c3, timeout_s=2.0, verbose=False):
        payload = pack4_signed16(c0, c1, c2, c3)
        old = self.status_dict()["command_counter"]
        self.send_cmd(CMD_SET_COEFF, payload, verbose=verbose)

        if not self.wait_command_seen(CMD_SET_COEFF, old_counter=old, timeout_s=0.3):
            st = self.status_dict()
            print("Aviso: o FPGA nao confirmou last_opcode=0x20 apos o envio.")
            print(f"       last_opcode=0x{st['last_opcode']:02X}, command_counter={st['command_counter']}")

        # Espera a pendencia do coeficiente ser consumida pelo FIR.
        t0 = time.perf_counter()
        while time.perf_counter() - t0 < timeout_s:
            st = self.status_dict()
            if st["coeff_overrun"]:
                raise RuntimeError("coeff_overrun=1 durante upload")
            # Quando o FIR aceita, coeff_pending volta para 0.
            if st["coeff_pending"] == 0:
                return st
            time.sleep(0.001)

        raise TimeoutError("Timeout esperando coeff_pending limpar")

    def upload_coeffs(self, coeffs, taps=None, verbose_each=100):
        coeffs = [sat_s16(x) for x in coeffs]
        if taps is not None:
            taps = int(taps)
            if len(coeffs) > taps:
                coeffs = coeffs[:taps]
            while len(coeffs) < taps:
                coeffs.append(0)

        while len(coeffs) % 4 != 0:
            coeffs.append(0)

        self.clear()
        print(f"Enviando {len(coeffs)} coeficientes para o FIR...")

        for i in range(0, len(coeffs), 4):
            st = self.send_coeff_block(coeffs[i], coeffs[i + 1], coeffs[i + 2], coeffs[i + 3])
            block_idx = i // 4
            if block_idx == 0 or ((block_idx + 1) % int(verbose_each) == 0):
                print(f"  bloco {block_idx + 1:5d} | coeff_count={st['coeff_count']} | last_opcode=0x{st['last_opcode']:02X}")

        # Espera contagem final, se taps foi informado.
        if taps is not None:
            t0 = time.perf_counter()
            while time.perf_counter() - t0 < 5.0:
                st = self.status_dict()
                if st["coeff_count"] >= taps or st["coeff_ok"]:
                    print(f"Upload finalizado. coeff_count={st['coeff_count']} coeff_ok={st['coeff_ok']}")
                    return st
                time.sleep(0.01)
            st = self.status_dict()
            raise TimeoutError(
                f"Timeout esperando coeff_count >= {taps}. "
                f"Status={st}"
            )

        st = self.status_dict()
        print(f"Upload finalizado. coeff_count={st['coeff_count']} coeff_ok={st['coeff_ok']}")
        return st

    def send_sample(self, value, timeout_s=2.0, verbose=False):
        value = sat_s16(value)
        old_result = self.status_dict()["result_counter16"]
        self.send_cmd(CMD_SET_SAMPLE, value & 0xFFFF, verbose=verbose)

        t0 = time.perf_counter()
        while time.perf_counter() - t0 < timeout_s:
            st = self.status_dict()
            if st["sample_overrun"]:
                raise RuntimeError("sample_overrun=1")
            if st["result_valid"] or st["result_counter16"] != old_result:
                return st["last_output"], st
            time.sleep(0.001)
        st = self.status_dict()
        raise TimeoutError(f"Timeout esperando resultado. Status={st}")

    def filter_file(self, input_file, output_file, column=None, max_samples=None):
        samples = read_samples_from_file(input_file, column=column)
        if max_samples is not None:
            samples = samples[:int(max_samples)]

        rows = []
        print(f"Filtrando {len(samples)} amostras...")
        for n, x in enumerate(samples):
            y, st = self.send_sample(x)
            rows.append({
                "n": n,
                "x": int(x),
                "y": int(y),
                "coeff_count": st["coeff_count"],
                "sample_counter": st["sample_counter"],
                "result_counter16": st["result_counter16"],
                "raw_data": st["raw_data"],
                "raw_export": st["raw_export"],
            })
            if n == 0 or (n + 1) % 100 == 0:
                print(f"  amostra {n + 1:6d}/{len(samples)} | x={x} | y={y}")

        df = pd.DataFrame(rows)
        output_file = str(output_file)
        if output_file.lower().endswith(".csv"):
            df.to_csv(output_file, index=False)
        else:
            df.to_pickle(output_file)
        print(f"Arquivo salvo: {output_file}")
        return df


def print_help():
    print(f"""
Terminal FIR 1 canal
Bridge base atual: 0x{BRIDGE:08X}

Comandos:
  help
  q

Debug:
  status
  raw
  clear
  seq <valor>
  cmd <opcode> [payload]
      exemplo: cmd 0x20 0x0000000000010000
      exemplo: cmd 0x40 1000

Coeficientes:
  coeffs <c0> <c1> ...
      exemplo: coeffs 0 1 1

  coeff_pkl <arquivo.pkl> [taps] [chave]
      exemplo: coeff_pkl sbmicro/fir/coeffs_2000.pkl 2000
      exemplo: coeff_pkl coeffs.pkl 128 coeff

  coeff_file <arquivo.pkl/txt/csv> [taps] [coluna_ou_chave]

Amostras:
  sample <valor>
      exemplo: sample 1000

  filter <entrada.pkl/csv/txt> <saida.pkl/csv> [coluna] [max_amostras]
      exemplo: filter sinal.pkl saida.pkl accel_1

Fluxo completo:
  run <coeffs.pkl> <entrada.pkl/csv/txt> <saida.pkl/csv> [taps] [coluna]
      exemplo: run coeffs.pkl sinal.pkl saida.pkl 2000 accel_1
""")


def main():
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    try:
        mm = mmap.mmap(
            fd,
            BRIDGE_SPAN,
            flags=mmap.MAP_SHARED,
            prot=mmap.PROT_READ | mmap.PROT_WRITE,
            offset=BRIDGE,
        )
        try:
            cli = FirTerminal(mm)
            # Zera o comando no inicio para garantir que o primeiro comando mude IN_B.
            write_u64(mm, IN_B, 0)
            print("=== FIR 1 canal - HPS terminal debug ===")
            print_help()

            while True:
                s = input("fir> ").strip()
                if not s:
                    continue
                if s.lower() in ("q", "quit", "exit"):
                    print("Saindo...")
                    break

                p = s.split()
                cmd = p[0].lower()

                try:
                    if cmd == "help":
                        print_help()

                    elif cmd == "status":
                        cli.status()

                    elif cmd == "raw":
                        print(f"IN_A       = 0x{read_u64(mm, IN_A):016X}  (readback pode depender do PIO)")
                        print(f"IN_B       = 0x{read_u64(mm, IN_B):016X}  (readback pode depender do PIO)")
                        print(f"OUT_EXPORT = 0x{cli.raw_export():016X}")
                        print(f"OUT_DATA   = 0x{cli.raw_data():016X}")

                    elif cmd == "clear":
                        cli.clear()

                    elif cmd == "seq" and len(p) == 2:
                        cli.seq = parse_int_auto(p[1]) & ((1 << 56) - 1)
                        print(f"seq = {cli.seq}")

                    elif cmd == "cmd" and len(p) in (2, 3):
                        opcode = parse_int_auto(p[1])
                        data = parse_int_auto(p[2]) if len(p) == 3 else 0
                        cli.send_cmd(opcode, data, verbose=True)
                        cli.status()

                    elif cmd == "coeffs" and len(p) >= 2:
                        coeffs = [parse_int_auto(x) for x in p[1:]]
                        cli.upload_coeffs(coeffs, taps=None)

                    elif cmd == "coeff_pkl" and len(p) in (2, 3, 4):
                        filename = p[1]
                        taps = parse_int_auto(p[2]) if len(p) >= 3 else None
                        key = p[3] if len(p) == 4 else None
                        coeffs = read_coeffs_file(filename, key=key)
                        cli.upload_coeffs(coeffs, taps=taps)

                    elif cmd == "coeff_file" and len(p) in (2, 3, 4):
                        filename = p[1]
                        taps = parse_int_auto(p[2]) if len(p) >= 3 else None
                        key = p[3] if len(p) == 4 else None
                        coeffs = read_coeffs_file(filename, key=key, column=key)
                        cli.upload_coeffs(coeffs, taps=taps)

                    elif cmd == "sample" and len(p) == 2:
                        y, st = cli.send_sample(parse_int_auto(p[1]), verbose=True)
                        print(f"y = {y}")
                        print(f"status: coeff_count={st['coeff_count']} result_valid={st['result_valid']} result_counter16={st['result_counter16']}")

                    elif cmd == "filter" and len(p) in (3, 4, 5):
                        input_file = p[1]
                        output_file = p[2]
                        column = p[3] if len(p) >= 4 else None
                        max_samples = parse_int_auto(p[4]) if len(p) == 5 else None
                        cli.filter_file(input_file, output_file, column=column, max_samples=max_samples)

                    elif cmd == "run" and len(p) in (4, 5, 6):
                        coeff_file = p[1]
                        input_file = p[2]
                        output_file = p[3]
                        taps = parse_int_auto(p[4]) if len(p) >= 5 else None
                        column = p[5] if len(p) == 6 else None
                        coeffs = read_coeffs_file(coeff_file)
                        cli.upload_coeffs(coeffs, taps=taps)
                        cli.filter_file(input_file, output_file, column=column)

                    else:
                        print("Comando invalido.")
                        print_help()

                except Exception as e:
                    print(f"Erro: {e}")

        finally:
            mm.close()
    finally:
        os.close(fd)    


if __name__ == "__main__":
    main()
