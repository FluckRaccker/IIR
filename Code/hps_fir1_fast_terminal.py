import os
import mmap
import struct
import time
import re
import shlex
from pathlib import Path

import pandas as pd

# ============================================================
# Enderecos da bridge
# ============================================================
BRIDGE = 0xC0000000
BRIDGE_SPAN = 0x100

IN_A       = 0x00
IN_B       = 0x08
OUT_EXPORT = 0x10
OUT_DATA   = 0x18

# ============================================================
# Opcodes
# ============================================================
CMD_NOP           = 0x00
CMD_SET_COEFF     = 0x20
CMD_SET_COEFF_WS  = 0x21
CMD_CLEAR_PENDING = 0x22
CMD_CLEAR_OVERRUN = 0x23
CMD_SET_SAMPLE    = 0x40
CMD_CLEAR_RESULT  = 0x41

U64 = struct.Struct("<Q")
MASK64 = 0xFFFFFFFFFFFFFFFF

# ============================================================
# Acesso basico rapido
# ============================================================
def write_u64(mm, offset, value):
    U64.pack_into(mm, offset, int(value) & MASK64)


def read_u64(mm, offset):
    return U64.unpack_from(mm, offset)[0]


def parse_int_auto(text):
    return int(str(text), 0)


def to_signed(x, bits):
    x = int(x) & ((1 << bits) - 1)
    if x & (1 << (bits - 1)):
        return x - (1 << bits)
    return x


def sat_signed(value, bits=16):
    value = int(round(float(value)))
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo:
        return lo
    if value > hi:
        return hi
    return value


def pack4_signed16(c0, c1, c2, c3):
    payload = 0
    for i, c in enumerate([c0, c1, c2, c3]):
        payload |= (sat_signed(c, 16) & 0xFFFF) << (16 * i)
    return payload & MASK64


# ============================================================
# Decode dos registradores do FPGA
# ============================================================
def unpack_out_data(raw):
    raw &= MASK64

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

        "fir_ready":          (status_flags >> 0) & 1,
        "coeff_pending":      (status_flags >> 1) & 1,
        "sample_pending":     (status_flags >> 2) & 1,
        "coeff_overrun":      (status_flags >> 3) & 1,
        "sample_overrun":     (status_flags >> 4) & 1,
        "coeff_ok":           (status_flags >> 5) & 1,
        "result_valid":       (status_flags >> 6) & 1,
        "fir_en_last":        (status_flags >> 7) & 1,
    }


def unpack_out_export(raw):
    raw &= MASK64

    y_u16 = (raw >> 48) & 0xFFFF
    x_u16 = (raw >> 32) & 0xFFFF
    result_counter16 = (raw >> 16) & 0xFFFF
    sample_counter16 = raw & 0xFFFF

    return {
        "raw_export": raw,
        "last_output": to_signed(y_u16, 16),
        "last_input": to_signed(x_u16, 16),
        "result_counter16": result_counter16,
        "sample_counter16": sample_counter16,
    }


# ============================================================
# Leitura de coeficientes e amostras
# ============================================================
def normalize_int_list(values):
    out = []
    for x in values:
        if pd.isna(x):
            continue
        out.append(sat_signed(x, 16))
    return out


def read_numbers_txt(filename):
    text = Path(filename).read_text(encoding="utf-8", errors="ignore")
    lines = []
    for line in text.splitlines():
        line = line.split("#", 1)[0]
        lines.append(line)
    text = "\n".join(lines)
    tokens = re.split(r"[,;\s]+", text.strip())
    tokens = [t for t in tokens if t]
    return [sat_signed(parse_int_auto(t), 16) for t in tokens]


def read_numbers_csv(filename, column=None):
    path = Path(filename)
    try:
        df = pd.read_csv(path)
    except Exception:
        df = pd.read_csv(path, header=None)

    if column is not None:
        if column not in df.columns:
            raise ValueError(f"Coluna '{column}' nao encontrada. Colunas: {list(df.columns)}")
        return normalize_int_list(df[column].tolist())

    for preferred in ["coeff", "coeffs", "sample", "samples", "x", "accel_1"]:
        if preferred in df.columns:
            return normalize_int_list(df[preferred].tolist())

    numeric_cols = df.select_dtypes(include="number").columns
    if len(numeric_cols) == 0:
        raise ValueError("CSV nao tem coluna numerica.")

    return normalize_int_list(df[numeric_cols[0]].tolist())


def extract_numbers_from_pkl_object(obj, key=None):
    """
    Aceita:
      - lista/tupla/array
      - dict com chaves como coeff, coeffs, wf, ws
      - DataFrame com coluna indicada ou primeira coluna numerica
      - Series
    """
    if isinstance(obj, dict):
        if key is None:
            for k in ["coeff", "coeffs", "h", "fir", "wf", "ws", "samples", "x", "accel_1"]:
                if k in obj:
                    key = k
                    break
        if key is None:
            raise ValueError(f"PKL e dict. Informe uma chave. Chaves disponiveis: {list(obj.keys())}")
        if key not in obj:
            raise ValueError(f"Chave '{key}' nao encontrada. Chaves disponiveis: {list(obj.keys())}")
        return normalize_int_list(obj[key])

    if isinstance(obj, pd.DataFrame):
        if key is not None:
            if key not in obj.columns:
                raise ValueError(f"Coluna '{key}' nao encontrada. Colunas: {list(obj.columns)}")
            return normalize_int_list(obj[key].tolist())

        for preferred in ["coeff", "coeffs", "sample", "samples", "x", "accel_1"]:
            if preferred in obj.columns:
                return normalize_int_list(obj[preferred].tolist())

        numeric_cols = obj.select_dtypes(include="number").columns
        if len(numeric_cols) == 0:
            raise ValueError("DataFrame nao tem coluna numerica.")
        return normalize_int_list(obj[numeric_cols[0]].tolist())

    if isinstance(obj, pd.Series):
        return normalize_int_list(obj.tolist())

    if hasattr(obj, "tolist"):
        obj = obj.tolist()

    if isinstance(obj, (list, tuple)):
        return normalize_int_list(obj)

    raise ValueError("Formato de PKL nao reconhecido.")


def read_numbers_file(filename, key_or_column=None):
    suffix = Path(filename).suffix.lower()
    if suffix == ".pkl":
        return extract_numbers_from_pkl_object(pd.read_pickle(filename), key=key_or_column)
    if suffix == ".csv":
        return read_numbers_csv(filename, column=key_or_column)
    if suffix == ".txt":
        return read_numbers_txt(filename)
    raise ValueError("Formato nao suportado. Use .pkl, .csv ou .txt.")


# ============================================================
# Classe principal
# ============================================================
class FirBridgeCLI:
    def __init__(self, mm):
        self.mm = mm
        self.seq = 0

    def next_seq(self):
        self.seq = (self.seq + 1) & ((1 << 56) - 1)
        if self.seq == 0:
            self.seq = 1
        return self.seq

    def send_cmd(self, opcode, data=0, delay_s=0.0):
        cmd_word = (self.next_seq() << 8) | (int(opcode) & 0xFF)
        write_u64(self.mm, IN_A, data)
        write_u64(self.mm, IN_B, cmd_word)
        if delay_s > 0:
            time.sleep(delay_s)

    # ------------------------------------------------------------
    # Leituras
    # ------------------------------------------------------------
    def raw_data(self):
        return read_u64(self.mm, OUT_DATA)

    def raw_export(self):
        return read_u64(self.mm, OUT_EXPORT)

    def read_status(self):
        return unpack_out_data(self.raw_data())

    def read_export(self):
        return unpack_out_export(self.raw_export())

    def status(self):
        st = self.read_status()
        ex = self.read_export()

        print(f"OUT_DATA   = 0x{st['raw_data']:016X}")
        print(f"OUT_EXPORT = 0x{ex['raw_export']:016X}")
        print("")
        print(f"last_opcode       = 0x{st['last_opcode']:02X}")
        print(f"command_counter   = {st['command_counter']}")
        print(f"coeff_count       = {st['coeff_count']}")
        print(f"sample_counter    = {st['sample_counter']}")
        print(f"result_counter16  = {ex['result_counter16']}")
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
        print(f"last_input        = {ex['last_input']}")
        print(f"last_output       = {ex['last_output']}")
        return st, ex

    # ------------------------------------------------------------
    # Limpeza
    # ------------------------------------------------------------
    def clear(self):
        self.send_cmd(CMD_CLEAR_PENDING, 0)
        self.send_cmd(CMD_CLEAR_OVERRUN, 0)
        self.send_cmd(CMD_CLEAR_RESULT, 0)
        print("Pending, overrun e result_valid limpos.")

    # ------------------------------------------------------------
    # Coeficientes
    # ------------------------------------------------------------
    def upload_coeffs_fast(self, coeffs, ntaps=None, key_name="", print_every=100, wait_end=True):
        coeffs = [sat_signed(c, 16) for c in coeffs]
        if ntaps is not None:
            ntaps = int(ntaps)
            coeffs = coeffs[:ntaps]

        # Pad para multiplo de 4 porque cada comando carrega 4 coeficientes.
        while len(coeffs) % 4 != 0:
            coeffs.append(0)

        print(f"Enviando {len(coeffs)} coeficientes para o FIR{(' [' + key_name + ']') if key_name else ''}...")
        t0 = time.perf_counter()

        for block_idx, i in enumerate(range(0, len(coeffs), 4)):
            payload = pack4_signed16(coeffs[i], coeffs[i + 1], coeffs[i + 2], coeffs[i + 3])
            self.send_cmd(CMD_SET_COEFF, payload, delay_s=0.0)

            if print_every and (block_idx % print_every == 0):
                st = self.read_status()
                print(f"  bloco {block_idx:6d} | coeff_count={st['coeff_count']} | last_opcode=0x{st['last_opcode']:02X}")

        dt = time.perf_counter() - t0
        print(f"Upload enviado em {dt:.4f} s ({len(coeffs)/max(dt,1e-9):.1f} coef/s).")

        if wait_end and ntaps is not None:
            self.wait_coeff_count(ntaps, timeout_s=3.0)
            st = self.read_status()
            print(f"Upload finalizado. coeff_count={st['coeff_count']} coeff_ok={st['coeff_ok']}")

    def wait_coeff_count(self, target, timeout_s=3.0):
        t0 = time.perf_counter()
        target = int(target)
        last = None
        while True:
            st = self.read_status()
            last = st
            if st["coeff_count"] >= target:
                return st
            if time.perf_counter() - t0 > timeout_s:
                raise TimeoutError(f"Timeout esperando coeff_count >= {target}. Status={last}")
            time.sleep(0.001)

    # ------------------------------------------------------------
    # Amostras
    # ------------------------------------------------------------
    def send_sample_fast(self, x):
        data = sat_signed(x, 16) & 0xFFFF
        self.send_cmd(CMD_SET_SAMPLE, data, delay_s=0.0)

    def sample(self, x, read_result=True):
        self.send_sample_fast(x)
        if read_result:
            # O HPS e bem mais lento que o clock do FPGA; normalmente uma leitura imediata ja pega o resultado.
            ex = self.read_export()
            print(f"x={sat_signed(x,16)} -> y={ex['last_output']} result_counter16={ex['result_counter16']}")
            return ex["last_output"]
        return None

    def filter_vector_fast(self, values, read_output=True, print_every=1000):
        x_values = [sat_signed(v, 16) for v in values]
        y_values = []
        rows = []

        t0 = time.perf_counter()

        for i, x in enumerate(x_values):
            self.send_sample_fast(x)

            if read_output:
                ex = self.read_export()
                y_values.append(ex["last_output"])
                rows.append({
                    "n": i,
                    "x": x,
                    "y": ex["last_output"],
                    "result_counter16": ex["result_counter16"],
                    "sample_counter16": ex["sample_counter16"],
                    "raw_export": ex["raw_export"],
                })

            if print_every and (i % print_every == 0):
                print(f"  {i}/{len(x_values)} amostras enviadas")

        dt = time.perf_counter() - t0
        rate = len(x_values) / max(dt, 1e-9)
        print(f"Tempo: {dt:.4f} s")
        print(f"Taxa:  {rate:.1f} amostras/s")

        if read_output:
            return pd.DataFrame(rows)
        return pd.DataFrame({"n": range(len(x_values)), "x": x_values})

    def bench_send(self, n=10000):
        n = int(n)
        t0 = time.perf_counter()
        for i in range(n):
            self.send_sample_fast(i)
        dt = time.perf_counter() - t0
        print(f"Enviadas {n} amostras em {dt:.4f} s")
        print(f"Taxa maxima de escrita: {n/max(dt,1e-9):.1f} amostras/s")


def print_help():
    print(r"""
Comandos:
  help
  q

Leitura/debug:
  status
  raw
  cmd <opcode> [data]
      exemplo: cmd 0x20 0x0000000000010000

Limpeza:
  clear
  clear_pending
  clear_overrun
  clear_result

Coeficientes:
  coeffs <c0> <c1> <c2> ...
      exemplo: coeffs 32767 0 0 0

  coeff_pkl <arquivo.pkl> <ntaps> [chave/coluna]
      exemplo: coeff_pkl sbmicro/fir/coeffs_100.pkl 100 coeffs
      exemplo: coeff_pkl sbmicro/fir/coeffs_100.pkl 100 coeff

  coeff_file <arquivo.pkl/csv/txt> <ntaps> [chave/coluna]

Amostras:
  sample <valor>
  sample_fast <valor>

Filtragem rapida:
  filter_fast <entrada.pkl/csv/txt> <saida.pkl/csv> <coluna/chave> [read_output=1] [print_every=1000]
      exemplo: filter_fast sweep.pkl sweep_fpga.pkl accel_1
      exemplo sem ler saida: filter_fast sweep.pkl sweep_fpga.pkl accel_1 0

  run_fast <coeff.pkl> <entrada.pkl/csv/txt> <saida.pkl/csv> <ntaps> <coluna_sinal> [chave_coeff=coeffs]
      exemplo: run_fast coeffs_100.pkl sweep.pkl sweep_fpga.pkl 100 accel_1 coeffs

Benchmark:
  bench <n>
      exemplo: bench 10000
""")


def save_dataframe(df, filename):
    suffix = Path(filename).suffix.lower()
    if suffix == ".csv":
        df.to_csv(filename, index=False)
    else:
        df.to_pickle(filename)


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
            cli = FirBridgeCLI(mm)
            write_u64(mm, IN_B, 0)

            print("=== FIR 1 canal - terminal rapido HPS/FPGA ===")
            print_help()

            while True:
                try:
                    s = input("fir> ").strip()
                except EOFError:
                    print()
                    break

                if not s:
                    continue

                p = shlex.split(s)
                cmd = p[0].lower()

                try:
                    if cmd in ("q", "quit", "exit"):
                        print("Saindo...")
                        break

                    elif cmd == "help":
                        print_help()

                    elif cmd == "status":
                        cli.status()

                    elif cmd == "raw":
                        print(f"OUT_DATA   = 0x{cli.raw_data():016X}")
                        print(f"OUT_EXPORT = 0x{cli.raw_export():016X}")

                    elif cmd == "cmd" and len(p) in (2, 3):
                        opcode = parse_int_auto(p[1])
                        data = parse_int_auto(p[2]) if len(p) == 3 else 0
                        cli.send_cmd(opcode, data)
                        st = cli.read_status()
                        print(f"cmd enviado: opcode=0x{opcode:02X} data=0x{data & MASK64:016X}")
                        print(f"last_opcode=0x{st['last_opcode']:02X} command_counter={st['command_counter']}")

                    elif cmd == "clear":
                        cli.clear()

                    elif cmd == "clear_pending":
                        cli.send_cmd(CMD_CLEAR_PENDING, 0)
                        print("Pending limpo.")

                    elif cmd == "clear_overrun":
                        cli.send_cmd(CMD_CLEAR_OVERRUN, 0)
                        print("Overrun limpo.")

                    elif cmd == "clear_result":
                        cli.send_cmd(CMD_CLEAR_RESULT, 0)
                        print("Result valid limpo.")

                    elif cmd == "coeffs" and len(p) >= 2:
                        coeffs = [parse_int_auto(x) for x in p[1:]]
                        cli.clear()
                        cli.upload_coeffs_fast(coeffs, ntaps=len(coeffs), print_every=10)

                    elif cmd in ("coeff_pkl", "coeff_file") and len(p) in (3, 4):
                        filename = p[1]
                        ntaps = parse_int_auto(p[2])
                        key = p[3] if len(p) == 4 else None
                        coeffs = read_numbers_file(filename, key_or_column=key)
                        cli.clear()
                        cli.upload_coeffs_fast(coeffs, ntaps=ntaps, key_name=key or "", print_every=100, wait_end=True)

                    elif cmd == "sample" and len(p) == 2:
                        cli.sample(parse_int_auto(p[1]), read_result=True)

                    elif cmd == "sample_fast" and len(p) == 2:
                        cli.send_sample_fast(parse_int_auto(p[1]))
                        print("Amostra enviada sem leitura de saida.")

                    elif cmd == "filter_fast" and len(p) in (4, 5, 6):
                        in_file = p[1]
                        out_file = p[2]
                        key = p[3]
                        read_output = bool(parse_int_auto(p[4])) if len(p) >= 5 else True
                        print_every = parse_int_auto(p[5]) if len(p) == 6 else 1000

                        values = read_numbers_file(in_file, key_or_column=key)
                        print(f"Enviando {len(values)} amostras em modo rapido...")
                        df_out = cli.filter_vector_fast(values, read_output=read_output, print_every=print_every)
                        save_dataframe(df_out, out_file)
                        print(f"Arquivo salvo: {out_file}")

                    elif cmd == "run_fast" and len(p) in (6, 7):
                        coeff_file = p[1]
                        in_file = p[2]
                        out_file = p[3]
                        ntaps = parse_int_auto(p[4])
                        signal_key = p[5]
                        coeff_key = p[6] if len(p) == 7 else "coeffs"

                        coeffs = read_numbers_file(coeff_file, key_or_column=coeff_key)
                        cli.clear()
                        cli.upload_coeffs_fast(coeffs, ntaps=ntaps, key_name=coeff_key, print_every=100, wait_end=True)

                        values = read_numbers_file(in_file, key_or_column=signal_key)
                        print(f"Filtrando {len(values)} amostras da coluna/chave '{signal_key}'...")
                        df_out = cli.filter_vector_fast(values, read_output=True, print_every=1000)
                        save_dataframe(df_out, out_file)
                        print(f"Arquivo salvo: {out_file}")

                    elif cmd == "bench" and len(p) == 2:
                        cli.bench_send(parse_int_auto(p[1]))

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
