import subprocess
from build_clash_universal import run


def upgrade_version(current_version):
    string = open('go.mod').read()
    string = string.replace(current_version, "dev")
    file = open("go.mod", "w")
    file.write(string)


def get_full_version():
    with open('./go.mod') as file:
        for line in file.readlines():
            if "clash" in line and "ClashX" not in line:
                return line.split(" ")[-1].strip()

def install():
    subprocess.check_output("go mod download", shell=True)
    subprocess.check_output("go mod tidy", shell=True)


if __name__ == '__main__':
    print("start")
    current = get_full_version()
    print("current version:", current)
    upgrade_version(current)
    install()
    new_version = get_full_version()
    print("new version:", new_version, ",start building")
    run()
