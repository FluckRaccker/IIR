#!/usr/bin/env python3
"""
hps_iir_pkl_terminal.py

Terminal interativo para controlar um IIR biquad reconfiguravel pelo HPS usando /dev/mem.

Fluxo normal:

  sudo ./hps_iir_pkl_terminal.py

  iir>> coeff_pkl coeffs_iir.pkl float
  iir>> rc
  iir>> sample 1000
  iir>> filter_pkl entrada.pkl saida.pkl x
  iir>> q

Protocolo esperado no FPGA:

  IN_A[7:0]    = opcode/comando
  IN_A[10:8]   = indice do coeficiente
  IN_A[47:32]  = seq

  IN_B[15:0]   = dado signed16

Comandos:
  0x01 CMD_SAMPLE
  0x02 CMD_WRITE_COEFF
  0x03 CMD_READ_COEFF
  0x04 CMD_CLEAR_IIR

Resposta em OUT_EXPORT:
  OUT_EXPORT[63:56] = status
  OUT_EXPORT[55:48] = comando
  OUT_EXPORT[47:32] = seq
  OUT_EXPORT[31:16] = campo1
  OUT_EXPORT[15:0]  = campo0
"""

import os
import mmap
import struct
import time
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


# ============================================================
# Comandos do simple_cmd_storage do IIR
# ============================================================

CMD_NOP         = 0x00
CMD_SAMPLE      = 0x01
CMD_WRITE_COEFF = 0x02
CMD_READ_COEFF  = 0x03
CMD_CLEAR_IIR   = 0x04


# ============================================================
# Status esperados em OUT_EXPORT[63:56]
# ============================================================

STATUS_SAMPLE_ACK   = 0x10
STATUS_SAMPLE_READY = 0xA0
STATUS_COEFF_WRITE  = 0xB0
STATUS_COEFF_READ   = 0xC0
STATUS_CLEAR_IIR    = 0xD0
STATUS_ERROR        = 0xE1


# ============================================================
# Q2.14
# ============================================================

Q_SHIFT = 14
Q_SCALE = 1 << Q_SHIFT


# ============================================================
# Funcoes basicas
# ============================================================

def write_u64(mm, offset, value):
    mm[offset:offset + 8] = struct.pack("<Q", int(value) & 0xFFFFFFFFFFFFFFFF)


def read_u64(mm, offset):
    return struct.unpack("<Q", mm[offset:offset + 8])[0]


def parse_int_auto(text):
    return int(str(text), 0)


def sat_signed(value, bits=16):
    value = int(round(float(value)))

    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1

    if value < lo:
        return lo
    if value > hi:
        return hi

    return value


def to_signed(x, bits=16):
    x = int(x) & ((1 << bits) - 1)

    if x & (1 << (bits - 1)):
        return x - (1 << bits)

    return x


def s16_to_u16(x):
    return int(x) & 0xFFFF


def u16_to_s16(x):
    return to_signed(x, 16)


def float_to_q14(x):
    return sat_signed(float(x) * Q_SCALE, 16)


def q14_to_float(x):
    return float(to_signed(x, 16)) / Q_SCALE


def make_cmd(opcode, idx=0, seq=0):
    """
    Monta comando para IN_A.

    IN_A[7:0]    = opcode
    IN_A[10:8]   = idx
    IN_A[47:32]  = seq
    """
    return (
        ((int(seq) & 0xFFFF) << 32) |
        ((int(idx) & 0x7) << 8) |
        (int(opcode) & 0xFF)
    )


def parse_out_export(raw):
    raw &= 0xFFFFFFFFFFFFFFFF

    field1_u16 = (raw >> 16) & 0xFFFF
    field0_u16 = raw & 0xFFFF

    return {
        "raw": raw,
        "status": (raw >> 56) & 0xFF,
        "cmd":    (raw >> 48) & 0xFF,
        "seq":    (raw >> 32) & 0xFFFF,

        "field1_u16": field1_u16,
        "field0_u16": field0_u16,

        "field1_s16": u16_to_s16(field1_u16),
        "field0_s16": u16_to_s16(field0_u16),
    }


# ============================================================
# Leitura de PKL
# ============================================================

def normalize_numeric_list(values):
    out = []

    for v in values:
        if pd.isna(v):
            continue

        out.append(sat_signed(v, 16))

    return out


def read_samples_pkl(filename, column=None):
    """
    Le amostras de um .pkl.

    Aceita:
      - list
      - tuple
      - numpy array
      - pandas Series
      - pandas DataFrame
      - dict

    Colunas/chaves preferidas:
      x, sample, samples, data, accel_1, accel_2, y
    """
    path = Path(filename)
    obj = pd.read_pickle(path)

    preferred = ["x", "sample", "samples", "data", "accel_1", "accel_2", "y"]

    time_column = None
    samples = None

    if isinstance(obj, pd.DataFrame):
        if "t_s" in obj.columns:
            time_column = obj["t_s"].to_numpy()

        if column is not None:
            if column not in obj.columns:
                raise ValueError(f"Coluna '{column}' nao encontrada em {filename}")
            samples = normalize_numeric_list(obj[column].to_numpy())
            return samples, time_column

        for key in preferred:
            if key in obj.columns:
                samples = normalize_numeric_list(obj[key].to_numpy())
                return samples, time_column

        nums = obj.select_dtypes(include="number")
        if nums.shape[1] == 0:
            raise ValueError("DataFrame .pkl nao possui coluna numerica.")

        samples = normalize_numeric_list(nums.iloc[:, 0].to_numpy())
        return samples, time_column

    if isinstance(obj, dict):
        if "t_s" in obj:
            time_column = obj["t_s"]

        if column is not None:
            if column not in obj:
                raise ValueError(f"Chave '{column}' nao encontrada em {filename}")
            samples = normalize_numeric_list(obj[column])
            return samples, time_column

        for key in preferred:
            if key in obj:
                samples = normalize_numeric_list(obj[key])
                return samples, time_column

        raise ValueError(
            "Dict .pkl nao tem chave conhecida. Use uma chave como "
            "'x', 'sample', 'samples', 'data', 'accel_1' ou passe a coluna/chave."
        )

    if hasattr(obj, "tolist"):
        obj = obj.tolist()

    if isinstance(obj, (list, tuple)):
        samples = normalize_numeric_list(obj)
        return samples, time_column

    raise ValueError("Formato .pkl de amostras nao reconhecido.")


def read_coeffs_pkl(filename, column=None, coeff_format="q14"):
    """
    Le coeficientes do IIR de um .pkl.

    Ordem esperada:
      a1, a2, b0, b1, b2

    coeff_format:
      q14   -> valores ja estao em Q2.14
      float -> valores estao em float e serao convertidos para Q2.14
    """
    path = Path(filename)
    obj = pd.read_pickle(path)

    names = ["a1", "a2", "b0", "b1", "b2"]
    preferred = ["coeffs", "coeff", "iir", "biquad", "coeficientes"]

    values = None

    if isinstance(obj, pd.DataFrame):
        # Caso o DataFrame tenha colunas a1, a2, b0, b1, b2
        if all(name in obj.columns for name in names):
            values = [obj[name].iloc[0] for name in names]

        elif column is not None:
            if column not in obj.columns:
                raise ValueError(f"Coluna '{column}' nao encontrada em {filename}")
            values = obj[column].to_numpy()

        else:
            for key in preferred:
                if key in obj.columns:
                    values = obj[key].to_numpy()
                    break

            if values is None:
                nums = obj.select_dtypes(include="number")
                if nums.shape[1] == 0:
                    raise ValueError("DataFrame .pkl nao possui coluna numerica.")
                values = nums.iloc[:, 0].to_numpy()

    elif isinstance(obj, dict):
        # Caso o dict tenha a1, a2, b0, b1, b2
        if all(name in obj for name in names):
            values = [obj[name] for name in names]

        elif column is not None:
            if column not in obj:
                raise ValueError(f"Chave '{column}' nao encontrada em {filename}")
            values = obj[column]

        else:
            for key in preferred:
                if key in obj:
                    values = obj[key]
                    break

            if values is None:
                raise ValueError(
                    "Dict .pkl nao tem chave conhecida. Use uma chave como "
                    "'coeffs', 'coeff', 'iir', 'biquad' ou use a1/a2/b0/b1/b2."
                )

    else:
        if hasattr(obj, "tolist"):
            obj = obj.tolist()

        if isinstance(obj, (list, tuple)):
            values = obj
        else:
            raise ValueError("Formato .pkl de coeficientes nao reconhecido.")

    values = list(values)

    if len(values) < 5:
        raise ValueError("O arquivo de coeficientes precisa ter pelo menos 5 valores.")

    values = values[:5]

    if coeff_format.lower() in ("float", "f"):
        coeffs_q14 = [float_to_q14(v) for v in values]
    elif coeff_format.lower() in ("q14", "fixed", "int"):
        coeffs_q14 = [sat_signed(v, 16) for v in values]
    else:
        raise ValueError("coeff_format deve ser 'q14' ou 'float'.")

    return coeffs_q14


# ============================================================
# Classe principal do terminal IIR
# ============================================================

class IIRTerminal:
    def __init__(self, mm, poll_s=0.0002):
        self.mm = mm
        self.seq = 0
        self.poll_s = float(poll_s)

    def next_seq(self):
        self.seq = (self.seq + 1) & 0xFFFF

        if self.seq == 0:
            self.seq = 1

        return self.seq

    def raw_export(self):
        return read_u64(self.mm, OUT_EXPORT)

    def export_dict(self):
        return parse_out_export(self.raw_export())

    def raw(self):
        print(f"IN_A       = offset 0x{IN_A:02X}")
        print(f"IN_B       = offset 0x{IN_B:02X}")
        print(f"OUT_EXPORT = 0x{self.raw_export():016X}")

    def status(self):
        ex = self.export_dict()

        print(f"OUT_EXPORT = 0x{ex['raw']:016X}")
        print(f"status     = 0x{ex['status']:02X}")
        print(f"cmd        = 0x{ex['cmd']:02X}")
        print(f"seq        = {ex['seq']}")
        print(f"field1     = {ex['field1_s16']}")
        print(f"field0     = {ex['field0_s16']}")

    def wait_status(self, expected_status, expected_seq=None, timeout_s=1.0):
        t0 = time.perf_counter()

        while True:
            ex = self.export_dict()

            if ex["status"] == expected_status:
                if expected_seq is None or ex["seq"] == expected_seq:
                    return ex

            if time.perf_counter() - t0 > timeout_s:
                raise TimeoutError(
                    f"Timeout esperando status 0x{expected_status:02X}. "
                    f"Ultimo OUT_EXPORT = 0x{ex['raw']:016X}, "
                    f"status atual = 0x{ex['status']:02X}, seq atual = {ex['seq']}"
                )

            time.sleep(self.poll_s)

    # ------------------------------------------------------------
    # Controle do IIR
    # ------------------------------------------------------------

    def clear_iir(self):
        seq = self.next_seq()

        write_u64(self.mm, IN_B, 0)
        write_u64(self.mm, IN_A, make_cmd(CMD_CLEAR_IIR, seq=seq))

        self.wait_status(STATUS_CLEAR_IIR, expected_seq=seq)
        print("Estados internos do IIR limpos.")

    # ------------------------------------------------------------
    # Coeficientes
    # ------------------------------------------------------------

    def write_coeff(self, idx, value_q14):
        idx = int(idx)

        if not 0 <= idx <= 4:
            raise ValueError("idx deve estar entre 0 e 4")

        value_q14 = sat_signed(value_q14, 16)
        seq = self.next_seq()

        write_u64(self.mm, IN_B, s16_to_u16(value_q14))
        write_u64(self.mm, IN_A, make_cmd(CMD_WRITE_COEFF, idx=idx, seq=seq))

        self.wait_status(STATUS_COEFF_WRITE, expected_seq=seq)

    def read_coeff(self, idx):
        idx = int(idx)

        if not 0 <= idx <= 4:
            raise ValueError("idx deve estar entre 0 e 4")

        seq = self.next_seq()

        write_u64(self.mm, IN_B, 0)
        write_u64(self.mm, IN_A, make_cmd(CMD_READ_COEFF, idx=idx, seq=seq))

        ex = self.wait_status(STATUS_COEFF_READ, expected_seq=seq)

        return ex["field0_s16"]

    def write_coeffs_q14(self, coeffs):
        if len(coeffs) != 5:
            raise ValueError("Precisa enviar 5 coeficientes: a1 a2 b0 b1 b2")

        for idx, c in enumerate(coeffs):
            self.write_coeff(idx, c)

        print("Coeficientes escritos no FPGA.")

    def write_coeffs_float(self, coeffs_float):
        if len(coeffs_float) != 5:
            raise ValueError("Precisa enviar 5 coeficientes: a1 a2 b0 b1 b2")

        coeffs_q14 = [float_to_q14(c) for c in coeffs_float]
        self.write_coeffs_q14(coeffs_q14)

        print(f"Float: {coeffs_float}")
        print(f"Q2.14: {coeffs_q14}")

    def read_all_coeffs(self):
        coeffs_q14 = [self.read_coeff(i) for i in range(5)]
        coeffs_float = [q14_to_float(c) for c in coeffs_q14]

        print("Coeficientes atuais:")
        print(f"Q2.14: {coeffs_q14}")
        print(f"Float: {coeffs_float}")
        print("Ordem: a1 a2 b0 b1 b2")

        return coeffs_q14

    def upload_coeff_pkl(self, filename, coeff_format="q14", column=None):
        coeffs_q14 = read_coeffs_pkl(
            filename,
            column=column,
            coeff_format=coeff_format,
        )

        self.write_coeffs_q14(coeffs_q14)

        print(f"Arquivo de coeficientes: {filename}")
        print(f"Formato lido: {coeff_format}")
        print(f"Coeficientes Q2.14 enviados: {coeffs_q14}")
        print(f"Coeficientes float equivalentes: {[q14_to_float(c) for c in coeffs_q14]}")

    # ------------------------------------------------------------
    # Amostra
    # ------------------------------------------------------------

    def send_sample(self, value, timeout_s=1.0):
        x = sat_signed(value, 16)
        seq = self.next_seq()

        write_u64(self.mm, IN_B, s16_to_u16(x))
        write_u64(self.mm, IN_A, make_cmd(CMD_SAMPLE, seq=seq))

        ex = self.wait_status(
            STATUS_SAMPLE_READY,
            expected_seq=seq,
            timeout_s=timeout_s,
        )

        x_returned = ex["field1_s16"]
        y_filtered = ex["field0_s16"]

        return x_returned, y_filtered

    def sample(self, value):
        xr, y = self.send_sample(value)

        print(f"x enviado   = {sat_signed(value, 16)}")
        print(f"x retornado = {xr}")
        print(f"y filtrado  = {y}")

        return y

    # ------------------------------------------------------------
    # Filtragem de PKL
    # ------------------------------------------------------------

    def filter_values(self, samples, timeout_s=1.0, progress_every=1000):
        rows = []

        t0 = time.perf_counter()

        for n, x in enumerate(samples):
            xr, y = self.send_sample(x, timeout_s=timeout_s)

            rows.append({
                "n": n,
                "x": sat_signed(x, 16),
                "x_returned": xr,
                "y": y,
            })

            if progress_every > 0 and (n + 1) % progress_every == 0:
                elapsed = time.perf_counter() - t0
                rate = (n + 1) / elapsed if elapsed > 0 else 0
                print(f"{n + 1:8d} amostras | {rate:.1f} amostras/s")

        elapsed = time.perf_counter() - t0
        rate = len(samples) / elapsed if elapsed > 0 else 0

        print("Filtragem concluida.")
        print(f"Amostras: {len(samples)}")
        print(f"Tempo: {elapsed:.3f} s")
        print(f"Taxa media: {rate:.1f} amostras/s")

        return pd.DataFrame(rows)

    def filter_pkl(self, input_pkl, output_pkl, column=None, timeout_s=1.0):
        samples, time_column = read_samples_pkl(input_pkl, column=column)

        print(f"Arquivo de entrada: {input_pkl}")
        print(f"Amostras carregadas: {len(samples)}")

        df = self.filter_values(samples, timeout_s=timeout_s)

        if time_column is not None and len(time_column) >= len(df):
            df.insert(1, "t_s", list(time_column)[:len(df)])

        df.to_pickle(output_pkl)

        print(f"Arquivo de saida salvo: {output_pkl}")

    def run_pkl(self, coeff_pkl, input_pkl, output_pkl,
                coeff_format="q14", coeff_column=None, data_column=None):
        self.upload_coeff_pkl(
            coeff_pkl,
            coeff_format=coeff_format,
            column=coeff_column,
        )

        self.clear_iir()

        self.filter_pkl(
            input_pkl,
            output_pkl,
            column=data_column,
        )

    def filter_pkl_change_coeff(self, input_pkl, output_pkl, change_at,
                                new_coeff_pkl, coeff_format="q14",
                                data_column=None, coeff_column=None):
        samples, time_column = read_samples_pkl(input_pkl, column=data_column)

        new_coeffs_q14 = read_coeffs_pkl(
            new_coeff_pkl,
            column=coeff_column,
            coeff_format=coeff_format,
        )

        print(f"Filtrando {len(samples)} amostras.")
        print(f"Coeficientes serao reprogramados na amostra {change_at}.")

        rows = []
        t0 = time.perf_counter()

        for n, x in enumerate(samples):
            if n == int(change_at):
                print(f"Reprogramando coeficientes na amostra {n}...")
                self.write_coeffs_q14(new_coeffs_q14)
                print(f"Novos coeficientes Q2.14: {new_coeffs_q14}")

            xr, y = self.send_sample(x)

            rows.append({
                "n": n,
                "x": sat_signed(x, 16),
                "x_returned": xr,
                "y": y,
            })

            if (n + 1) % 1000 == 0:
                elapsed = time.perf_counter() - t0
                rate = (n + 1) / elapsed if elapsed > 0 else 0
                print(f"{n + 1:8d} amostras | {rate:.1f} amostras/s")

        df = pd.DataFrame(rows)

        if time_column is not None and len(time_column) >= len(df):
            df.insert(1, "t_s", list(time_column)[:len(df)])

        df.to_pickle(output_pkl)

        print(f"Arquivo de saida salvo: {output_pkl}")


# ============================================================
# Bridge
# ============================================================

def open_bridge():
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)

    mm = mmap.mmap(
        fd,
        BRIDGE_SPAN,
        flags=mmap.MAP_SHARED,
        prot=mmap.PROT_READ | mmap.PROT_WRITE,
        offset=BRIDGE,
    )

    return fd, mm


# ============================================================
# Help
# ============================================================

def print_help():
    print("""
Comandos:

  help
  q

Leitura:
  raw
      Mostra OUT_EXPORT bruto.

  status
      Decodifica OUT_EXPORT.

Controle:
  clear
      Limpa os estados internos do IIR.

Coeficientes:
  cf a1 a2 b0 b1 b2
      Envia coeficientes em float.
      Exemplo:
      cf 0 0 1 0 0

  cq a1 a2 b0 b1 b2
      Envia coeficientes em Q2.14.
      Exemplo:
      cq 0 0 16384 0 0

  coeff_pkl arquivo.pkl [formato] [coluna]
      Carrega coeficientes de arquivo PKL.
      formato pode ser q14 ou float.
      Default: q14

      Exemplos:
      coeff_pkl coeffs_iir_q14.pkl q14
      coeff_pkl coeffs_iir_float.pkl float
      coeff_pkl coeffs_iir.pkl float coeffs

  rc
      Le os coeficientes atuais do FPGA.

Amostra manual:
  sample valor
      Envia uma amostra signed16.
      Exemplo:
      sample 1000

Filtragem:
  filter_pkl entrada.pkl saida.pkl [coluna]
      Filtra amostras de um PKL usando os coeficientes atuais.
      Exemplos:
      filter_pkl entrada.pkl saida.pkl
      filter_pkl entrada.pkl saida.pkl accel_1

  run_pkl coeffs.pkl entrada.pkl saida.pkl [formato] [coluna_coeff] [coluna_dados]
      Carrega coeficientes e depois filtra dados.
      Exemplos:
      run_pkl coeffs.pkl entrada.pkl saida.pkl q14
      run_pkl coeffs.pkl entrada.pkl saida.pkl float coeffs accel_1

Reprogramacao durante a filtragem:
  change_pkl entrada.pkl saida.pkl N novos_coeffs.pkl [formato] [coluna_dados] [coluna_coeff]
      Filtra entrada.pkl e troca os coeficientes na amostra N.
      Exemplos:
      change_pkl entrada.pkl saida.pkl 8000 coeffs2.pkl float
      change_pkl entrada.pkl saida.pkl 8000 coeffs2.pkl float accel_1 coeffs
""")


# ============================================================
# Main interativo
# ============================================================

def main():
    fd = None
    mm = None

    try:
        fd, mm = open_bridge()

        # Zera comandos antigos
        write_u64(mm, IN_A, 0)
        write_u64(mm, IN_B, 0)
        time.sleep(0.01)

        cli = IIRTerminal(mm)

        print("=== Terminal HPS -> IIR reconfiguravel com PKL ===")
        print_help()

        while True:
            try:
                line = input("iir>> ").strip()
            except EOFError:
                print("\nSaindo...")
                break

            if not line:
                continue

            try:
                p = shlex.split(line)
                cmd = p[0].lower()

                if cmd in ("q", "quit", "exit"):
                    print("Saindo...")
                    break

                elif cmd == "help":
                    print_help()

                elif cmd == "raw":
                    cli.raw()

                elif cmd == "status":
                    cli.status()

                elif cmd == "clear":
                    cli.clear_iir()

                elif cmd == "cf" and len(p) == 6:
                    coeffs_float = [float(x) for x in p[1:6]]
                    cli.write_coeffs_float(coeffs_float)

                elif cmd == "cq" and len(p) == 6:
                    coeffs_q14 = [parse_int_auto(x) for x in p[1:6]]
                    cli.write_coeffs_q14(coeffs_q14)

                elif cmd == "coeff_pkl" and len(p) in (2, 3, 4):
                    filename = p[1]
                    coeff_format = p[2] if len(p) >= 3 else "q14"
                    column = p[3] if len(p) == 4 else None

                    cli.upload_coeff_pkl(
                        filename,
                        coeff_format=coeff_format,
                        column=column,
                    )

                elif cmd == "rc":
                    cli.read_all_coeffs()

                elif cmd == "sample" and len(p) == 2:
                    cli.sample(parse_int_auto(p[1]))

                elif cmd == "filter_pkl" and len(p) in (3, 4):
                    input_pkl = p[1]
                    output_pkl = p[2]
                    column = p[3] if len(p) == 4 else None

                    cli.filter_pkl(
                        input_pkl,
                        output_pkl,
                        column=column,
                    )

                elif cmd == "run_pkl" and len(p) in (4, 5, 6, 7):
                    coeff_pkl = p[1]
                    input_pkl = p[2]
                    output_pkl = p[3]

                    coeff_format = p[4] if len(p) >= 5 else "q14"
                    coeff_column = p[5] if len(p) >= 6 and p[5] != "-" else None
                    data_column = p[6] if len(p) >= 7 and p[6] != "-" else None

                    cli.run_pkl(
                        coeff_pkl,
                        input_pkl,
                        output_pkl,
                        coeff_format=coeff_format,
                        coeff_column=coeff_column,
                        data_column=data_column,
                    )

                elif cmd == "change_pkl" and len(p) in (5, 6, 7, 8):
                    input_pkl = p[1]
                    output_pkl = p[2]
                    change_at = parse_int_auto(p[3])
                    new_coeff_pkl = p[4]

                    coeff_format = p[5] if len(p) >= 6 else "q14"
                    data_column = p[6] if len(p) >= 7 and p[6] != "-" else None
                    coeff_column = p[7] if len(p) >= 8 and p[7] != "-" else None

                    cli.filter_pkl_change_coeff(
                        input_pkl,
                        output_pkl,
                        change_at,
                        new_coeff_pkl,
                        coeff_format=coeff_format,
                        data_column=data_column,
                        coeff_column=coeff_column,
                    )

                else:
                    print("Comando invalido. Use 'help'.")

            except Exception as exc:
                print(f"Erro: {exc}")

    finally:
        if mm is not None:
            mm.close()

        if fd is not None:
            os.close(fd)


if __name__ == "__main__":
    main()