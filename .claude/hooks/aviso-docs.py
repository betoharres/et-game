"""Avisa quando a documentacao esta atras do codigo.

Roda como hook SessionStart: a saida entra no contexto do agente. O limite e
baixo de proposito -- o custo de uma doc errada e maior que o de revisa-la.
"""
import subprocess
import sys
import time

LIMITE_COMMITS: int = 8
LIMITE_DIAS: int = 10
ALVOS: list[str] = ["docs/", "README.md", "AGENTS.md", "tools/VALIDACAO.md"]


def git(*args: str) -> str:
    try:
        saida = subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return saida.stdout.strip() if saida.returncode == 0 else ""


def main() -> int:
    marco: str = git("log", "-1", "--format=%H %ct", "--", *ALVOS)
    if not marco:
        return 0
    sha, _, carimbo = marco.partition(" ")
    commits: str = git("rev-list", "--count", f"{sha}..HEAD")
    if not commits.isdigit():
        return 0
    atrasados: int = int(commits)
    dias: int = int((time.time() - int(carimbo)) // 86400)
    if atrasados < LIMITE_COMMITS and dias < LIMITE_DIAS:
        return 0
    print(
        f"AVISO DE DOCUMENTACAO: {atrasados} commit(s) e {dias} dia(s) desde a "
        f"ultima revisao de docs/ (marco {sha[:8]}). Mencione isso ao usuario "
        "na sua proxima resposta e ofereca rodar a revisao de documentacao "
        "descrita em AGENTS.md. Nao revise por conta propria."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
