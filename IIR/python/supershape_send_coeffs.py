import audiofilter as af
from scipy import signal
import numpy as np
from tkinter import *
from tkinter import ttk, messagebox
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure
from matplotlib.ticker import LogLocator, EngFormatter, MultipleLocator
import subprocess
import shutil

Q15_SCALE = 2 ** 14


class SuperShapeFrame(Frame):
    def __init__(self, master=None):
        Frame.__init__(self, master)
        self.grid(padx=10, pady=10)
        self.last_coef = {}

        # ---------- Matplotlib ----------
        self.fig = Figure((15, 5.5), dpi=90)
        self.canvas = FigureCanvasTkAgg(self.fig, master=self)
        self.canvas.get_tk_widget().grid(row=0, column=0, columnspan=12, sticky="nsew")

        self.coef_text = Text(self, width=64, height=24, font=("Courier", 10))
        self.coef_text.grid(row=0, column=12, rowspan=14, padx=(10, 0), sticky="n")

        scroll = Scrollbar(self, command=self.coef_text.yview)
        scroll.grid(row=0, column=13, rowspan=14, sticky="ns")
        self.coef_text.config(yscrollcommand=scroll.set)

        gs = self.fig.add_gridspec(1, 2, width_ratios=[2, 1])
        self.ax_mag = self.fig.add_subplot(gs[0, 0])
        self.ax_z = self.fig.add_subplot(gs[0, 1])
        self._configure_axes(fs=48000)

        # ---------- Tk ----------
        self.ls_on = BooleanVar(value=True)
        self.peq_on = BooleanVar(value=True)
        self.hs_on = BooleanVar(value=True)

        Label(self, text="fs (Hz)").grid(row=1, column=0, sticky="w")
        self.fs_entry = Entry(self, width=10)
        self.fs_entry.insert(0, "48000")
        self.fs_entry.grid(row=1, column=1, sticky="w")

        # ---------- Low Shelf ----------
        Label(self, text="Low Shelf").grid(row=2, column=0, sticky="w")
        Checkbutton(self, text="On", variable=self.ls_on, command=self.refresh_figure).grid(row=2, column=1, sticky="w")

        Label(self, text="G (dB)").grid(row=3, column=0, sticky="w")
        self.ls_gain = Scale(self, from_=-18, to=18, orient=HORIZONTAL, command=lambda _: self.refresh_figure())
        self.ls_gain.set(-12)
        self.ls_gain.grid(row=3, column=1, columnspan=3, sticky="we")

        Label(self, text="fc (Hz)").grid(row=2, column=2, sticky="e")
        self.ls_fc = Entry(self, width=10)
        self.ls_fc.insert(0, "200")
        self.ls_fc.grid(row=2, column=3, sticky="w")

        # ---------- PEQ ----------
        Label(self, text="PEQ").grid(row=4, column=0, sticky="w")
        Checkbutton(self, text="On", variable=self.peq_on, command=self.refresh_figure).grid(row=4, column=1, sticky="w")

        Label(self, text="G (dB)").grid(row=5, column=0, sticky="w")
        self.peq_gain = Scale(self, from_=-18, to=18, orient=HORIZONTAL, command=lambda _: self.refresh_figure())
        self.peq_gain.set(12)
        self.peq_gain.grid(row=5, column=1, columnspan=3, sticky="we")

        Label(self, text="fm (Hz)").grid(row=4, column=2, sticky="e")
        self.peq_fm = Entry(self, width=10)
        self.peq_fm.insert(0, "10000")
        self.peq_fm.grid(row=4, column=3, sticky="w")

        Label(self, text="BW (Hz)").grid(row=4, column=4, sticky="e")
        self.peq_bw = Entry(self, width=10)
        self.peq_bw.insert(0, "2000")
        self.peq_bw.grid(row=4, column=5, sticky="w")

        # ---------- High Shelf ----------
        Label(self, text="High Shelf").grid(row=6, column=0, sticky="w")
        Checkbutton(self, text="On", variable=self.hs_on, command=self.refresh_figure).grid(row=6, column=1, sticky="w")

        Label(self, text="G (dB)").grid(row=7, column=0, sticky="w")
        self.hs_gain = Scale(self, from_=-18, to=18, orient=HORIZONTAL, command=lambda _: self.refresh_figure())
        self.hs_gain.set(12)
        self.hs_gain.grid(row=7, column=1, columnspan=3, sticky="we")

        Label(self, text="fc (Hz)").grid(row=6, column=2, sticky="e")
        self.hs_fc = Entry(self, width=10)
        self.hs_fc.insert(0, "1000")
        self.hs_fc.grid(row=6, column=3, sticky="w")

        # ---------- Envio SSH ----------
        Label(self, text="Filtro para enviar").grid(row=9, column=0, sticky="w")
        self.send_target = StringVar(value="LowShelf")
        ttk.Combobox(
            self,
            textvariable=self.send_target,
            values=("LowShelf", "PEQ", "HighShelf"),
            state="readonly",
            width=12,
        ).grid(row=9, column=1, sticky="w")

        Label(self, text="Usuário SSH").grid(row=10, column=0, sticky="w")
        self.ssh_user = Entry(self, width=14)
        self.ssh_user.insert(0, "root")
        self.ssh_user.grid(row=10, column=1, sticky="w")

        Label(self, text="IP/host SoC").grid(row=10, column=2, sticky="e")
        self.ssh_host = Entry(self, width=16)
        self.ssh_host.insert(0, "192.168.0.101")
        self.ssh_host.grid(row=10, column=3, sticky="w")

        Label(self, text="Script remoto").grid(row=11, column=0, sticky="w")
        self.remote_script = Entry(self, width=32)
        self.remote_script.insert(0, "/root/write_coeffs.py")
        self.remote_script.grid(row=11, column=1, columnspan=3, sticky="we")

        # ---------- Botões ----------
        Button(self, text="Run", command=self.refresh_figure).grid(row=8, column=2, sticky="we")
        Button(self, text="Reset", command=self.reset).grid(row=8, column=3, sticky="we")
        Button(self, text="Enviar coeficientes", command=self.send_selected_coeffs).grid(row=12, column=0, columnspan=4, sticky="we")

        for e in (self.fs_entry, self.ls_fc, self.peq_fm, self.peq_bw, self.hs_fc):
            e.bind("<Return>", lambda _evt: self.refresh_figure())

        self.refresh_figure()

    def _configure_axes(self, fs: float):
        self.ax_mag.clear()
        self.ax_mag.set_xscale("log")
        self.ax_mag.set_xlim(1, fs / 2)
        self.ax_mag.xaxis.set_major_locator(LogLocator(base=10))
        self.ax_mag.xaxis.set_major_formatter(EngFormatter(unit="Hz"))
        self.ax_mag.grid(True, which="both", axis="both", linestyle="-", linewidth=0.5, color=(0.8, 0.8, 0.8))
        self.ax_mag.set_title("Magnitude (cascata total)")
        self.ax_mag.set_ylabel("A (dB)")
        self.ax_mag.yaxis.set_major_locator(MultipleLocator(3))

    def _get_float(self, entry: Entry, default: float) -> float:
        try:
            return float(entry.get().strip())
        except Exception:
            return default

    def _build_sos(self, fs: float):
        sos_list = []
        coef = {}

        if self.ls_on.get():
            fc = self._get_float(self.ls_fc, 200.0)
            G = float(self.ls_gain.get())
            _, _, b, a = af.biquad_lshv2nd(fc, G, fs)
            sos_list.append([b[0], b[1], b[2], a[0], a[1], a[2]])
            coef["LowShelf"] = (np.array(b, dtype=float), np.array(a, dtype=float))

        if self.peq_on.get():
            fm = self._get_float(self.peq_fm, 10000.0)
            bw_hz = max(self._get_float(self.peq_bw, 2000.0), 1e-6)
            q = fm / bw_hz
            G = float(self.peq_gain.get())
            _, _, b, a = af.biquad_peq2nd(fm, G, q, fs)
            sos_list.append([b[0], b[1], b[2], a[0], a[1], a[2]])
            coef["PEQ"] = (np.array(b, dtype=float), np.array(a, dtype=float))

        if self.hs_on.get():
            fc = self._get_float(self.hs_fc, 1000.0)
            G = float(self.hs_gain.get())
            _, _, b, a = af.biquad_hshv1st(fc, G, fs)
            sos_list.append([b[0], b[1], b[2], a[0], a[1], a[2]])
            coef["HighShelf"] = (np.array(b, dtype=float), np.array(a, dtype=float))

        if len(sos_list) == 0:
            sos = np.array([[1, 0, 0, 1, 0, 0]], dtype=float)
        else:
            sos = np.array(sos_list, dtype=float)

        return sos, coef

    def refresh_figure(self):
        fs = max(self._get_float(self.fs_entry, 48000.0), 1.0)
        sos, coef = self._build_sos(fs)
        self.last_coef = coef

        b, a = signal.sos2tf(sos)
        z, p, k = signal.tf2zpk(b, a)
        f, H = signal.sosfreqz(sos, worN=2 ** 16, fs=fs)

        self._update_coef_box(coef, fs)

        self.ax_mag.cla()
        self._configure_axes(fs)
        self.ax_mag.plot(f, 20 * np.log10(np.maximum(np.abs(H), 1e-15)), lw=2)
        self.ax_mag.relim()
        self.ax_mag.autoscale(axis="y")
        self._zplane_plot(z, p, k)
        self.fig.tight_layout()
        self.canvas.draw_idle()

    def reset(self):
        self.ls_on.set(True)
        self.peq_on.set(True)
        self.hs_on.set(True)

        self.ls_gain.set(-12)
        self.peq_gain.set(12)
        self.hs_gain.set(12)

        for entry, val in [
            (self.fs_entry, "48000"),
            (self.ls_fc, "200"),
            (self.peq_fm, "10000"),
            (self.peq_bw, "2000"),
            (self.hs_fc, "1000"),
        ]:
            entry.delete(0, END)
            entry.insert(0, val)

        self.send_target.set("LowShelf")
        self.refresh_figure()

    def _float_to_q15(self, x: float) -> int:
        value = int(round(float(x) * Q15_SCALE))
        if value > 32767:
            value = 32767
        if value < -32768:
            value = -32768
        return value

    def _build_fpga_words(self, b, a):
        # Ordem assumida no FPGA:
        # coeff0 -> a1, coeff1 -> a2, coeff2 -> b0, coeff3 -> b1, coeff4 -> b2
        a1 = self._float_to_q15(a[1])
        a2 = self._float_to_q15(a[2])
        b0 = self._float_to_q15(b[0])
        b1 = self._float_to_q15(b[1])
        b2 = self._float_to_q15(b[2])

        word64 = (
            ((b1 & 0xFFFF) << 48)
            | ((b0 & 0xFFFF) << 32)
            | ((a2 & 0xFFFF) << 16)
            | (a1 & 0xFFFF)
        )
        word16 = b2 & 0xFFFF

        return {
            "a1": a1,
            "a2": a2,
            "b0": b0,
            "b1": b1,
            "b2": b2,
            "word64": word64,
            "word16": word16,
            "cmd1": f"wb 4 0x{word64:016X}",
            "cmd2": f"wb 1 0x{word16:04X}",
        }

    def _update_coef_box(self, coef: dict, fs: float):
        def fmt_vec(v):
            return "  ".join([f"{x: .8e}" for x in v])

        lines = [f"fs = {fs:.2f} Hz\n"]

        if not coef:
            lines.append("(nenhum filtro ligado)\n")
        else:
            for name, (b, a) in coef.items():
                packed = self._build_fpga_words(b, a)
                lines.append(f"[{name}]")
                lines.append(f"b: {fmt_vec(b)}")
                lines.append(f"a: {fmt_vec(a)}")
                lines.append(
                    "Q15: "
                    f"a1={packed['a1']}  a2={packed['a2']}  "
                    f"b0={packed['b0']}  b1={packed['b1']}  b2={packed['b2']}"
                )
                lines.append(packed["cmd1"])
                lines.append(packed["cmd2"])
                lines.append("")

        lines.append("Observação: o botão envia apenas um biquad por vez.")
        lines.append("Se vários filtros estiverem ligados, escolha qual seção enviar.")

        self.coef_text.delete("1.0", END)
        self.coef_text.insert("1.0", "\n".join(lines))

    def send_selected_coeffs(self):
        target = self.send_target.get().strip()
        if target not in self.last_coef:
            messagebox.showerror(
                "Filtro indisponível",
                f"O filtro '{target}' não está ativo. Ligue essa seção antes de enviar.",
            )
            return

        if shutil.which("ssh") is None:
            messagebox.showerror("SSH não encontrado", "Não encontrei o executável 'ssh' no PATH do Windows.")
            return

        user = self.ssh_user.get().strip()
        host = self.ssh_host.get().strip()
        remote_script = self.remote_script.get().strip()

        if not user or not host or not remote_script:
            messagebox.showerror("Dados incompletos", "Preencha usuário SSH, host e caminho do script remoto.")
            return

        b, a = self.last_coef[target]
        packed = self._build_fpga_words(b, a)

        ssh_target = f"{user}@{host}"
        remote_cmd = (
            f"python3 {remote_script} "
            f"0x{packed['word64']:016X} 0x{packed['word16']:04X}"
        )

        try:
            proc = subprocess.run(
                ["ssh", ssh_target, remote_cmd],
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
        except subprocess.TimeoutExpired:
            messagebox.showerror(
                "Timeout SSH",
                "A conexão expirou. Se o login ainda pede senha, configure chave SSH para envio automático.",
            )
            return
        except Exception as exc:
            messagebox.showerror("Erro SSH", str(exc))
            return

        if proc.returncode != 0:
            msg = proc.stderr.strip() or proc.stdout.strip() or "Falha no envio via SSH."
            messagebox.showerror("Falha no envio", msg)
            return

        messagebox.showinfo(
            "Envio concluído",
            f"Filtro enviado: {target}\n\n"
            f"{packed['cmd1']}\n"
            f"{packed['cmd2']}\n\n"
            f"Resposta do SoC:\n{proc.stdout.strip() or '(sem saída)'}",
        )

    def _zplane_plot(self, z, p, k):
        ax = self.ax_z
        ax.clear()

        theta = np.linspace(0, 2 * np.pi, 512)
        ax.plot(np.cos(theta), np.sin(theta), color="gray")

        if len(z) > 0:
            ax.plot(np.real(z), np.imag(z), "o", mfc="none", mec="blue", ms=8, label="zeros")

        if len(p) > 0:
            ax.plot(np.real(p), np.imag(p), "x", color="red", ms=8, label="poles")

        ax.set_title("Z-plane")
        ax.set_xlabel("Re{z}")
        ax.set_ylabel("Im{z}")
        ax.set_aspect("equal")
        ax.set_xlim(-1.5, 1.5)
        ax.set_ylim(-1.5, 1.5)
        ax.grid(True)


app = SuperShapeFrame()
app.master.title("EQ Cascade (SOS + sosfreqz + SSH)")
app.mainloop()
