import os
import re
import sys
import subprocess
import argparse
from collections import defaultdict
from datetime import datetime, timezone

TARGET_EXTENSIONS = ('.py', '.cpp', '.h', '.hpp', '.c', '.cxx')
TARGET_FOLDERS = ('HOMEWORKS', 'LABS', 'EXERCISES', 'PROJECTS')

MIN_LOGIC_TOKENS = 25

CXX_KEYWORDS = {
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double',
    'else', 'enum', 'extern', 'float', 'for', 'goto', 'if', 'inline', 'int', 'long',
    'register', 'restrict', 'return', 'short', 'signed', 'sizeof', 'static', 'struct',
    'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', 'bool',
    'class', 'const_cast', 'delete', 'dynamic_cast', 'explicit', 'false', 'friend',
    'mutable', 'namespace', 'new', 'operator', 'private', 'protected', 'public',
    'reinterpret_cast', 'static_cast', 'template', 'this', 'throw', 'true', 'try',
    'catch', 'typeid', 'typename', 'using', 'virtual', 'wchar_t', 'alignas', 'alignof',
    'constexpr', 'decltype', 'noexcept', 'nullptr', 'static_assert', 'thread_local'
}

def remove_comments(code: str) -> str:
    code = re.sub(r'//.*', '', code)
    code = re.sub(r'/\*.*?\*/', '', code, flags=re.DOTALL)
    return code

def normalize_exact_code(code: str) -> str:
    lines = [line.strip() for line in code.splitlines() if line.strip()]
    return '\n'.join(lines)

def tokenize(code: str):
    token_pattern = r'''
        "(?:[^"\\]|\\.)*" |          
        '(?:[^'\\]|\\.)*' |          
        \b\d+(?:\.\d+)?\b |          
        \b[A-Za-z_][A-Za-z0-9_]*\b | 
        [{}()\[\];,] |               
        [+\-*/%<>=!&|^~?:]           
    '''
    return re.findall(token_pattern, code, re.VERBOSE)

def is_identifier(token: str) -> bool:
    return re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', token) is not None

def normalize_tokens(tokens):
    normalized = []
    var_counter = 0
    for token in tokens:
        if is_identifier(token) and token not in CXX_KEYWORDS:
            normalized.append(f'ID{var_counter}')
            var_counter += 1
        else:
            normalized.append(token)
    return normalized

def extract_functions_excluding_main(code: str) -> str:
    lines = code.splitlines()
    in_function = False
    brace_count = 0
    current_function = []
    functions = []

    i = 0
    while i < len(lines):
        line = lines[i]
        func_match = re.match(r'^\s*([\w:~<>\[\]\*\&\s]+)\s+(\w+)\s*\([^)]*\)\s*{?\s*$', line)
        if func_match and not in_function:
            if func_match.group(2) in ('main', 'maint'):
                i += 1
                continue
            in_function = True
            current_function = [line]
            brace_count = 1 if '{' in line else 0
        elif in_function:
            current_function.append(line)
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0:
                functions.append('\n'.join(current_function))
                in_function = False
        i += 1
    return '\n'.join(functions)

def extract_logic_excluding_main(code: str) -> str:
    lines = code.splitlines()
    filtered_lines = []
    in_main = False
    brace_count = 0

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if re.match(r'^\s*(?:int|void)\s+main\s*\(', stripped) or re.match(r'^\s*int\s+main\s*$', stripped):
            in_main = True
            brace_count = stripped.count('{') - stripped.count('}')
            if brace_count <= 0:
                i += 1
                while i < len(lines):
                    brace_count += lines[i].count('{') - lines[i].count('}')
                    if brace_count <= 0: break
                    i += 1
                i += 1
                continue
        if in_main:
            brace_count += line.count('{') - line.count('}')
            if brace_count <= 0: in_main = False
        else:
            filtered_lines.append(line)
        i += 1
    return '\n'.join(filtered_lines)

def get_signatures(filepath: str):
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            raw = f.read()
    except Exception:
        return None, None

    clean = remove_comments(raw)
    exact_funcs = extract_functions_excluding_main(normalize_exact_code(clean))
    exact_sig = normalize_exact_code(exact_funcs)
    logic_clean = extract_logic_excluding_main(clean)
    logic_clean = re.sub(r'^[ \t]*#.*$', '', logic_clean, flags=re.MULTILINE)
    logic_tokens = normalize_tokens(tokenize(logic_clean))
    logic_sig = ' '.join(logic_tokens) if len(logic_tokens) >= MIN_LOGIC_TOKENS else ''
    
    return exact_sig, logic_sig

def scan_folder(folder_path):
    exact_map = {}
    logic_map = {}
    for root, _, files in os.walk(folder_path):
        for f in files:
            if f.endswith(TARGET_EXTENSIONS):
                p = os.path.join(root, f)
                e_sig, l_sig = get_signatures(p)
                if e_sig and e_sig.strip(): exact_map[p] = e_sig
                if l_sig and l_sig.strip(): logic_map[p] = l_sig
    return exact_map, logic_map

def first_commit_info(path: str, repo_root: str):
    """(unix_ts, author) самого раннего коммита, добавившего файл, либо None."""
    try:
        rel = os.path.relpath(path, repo_root)
        out = subprocess.run(
            ['git', '-C', repo_root, 'log', '--diff-filter=A', '--format=%at|%an', '--', rel],
            capture_output=True, text=True, check=True, timeout=60
        ).stdout.strip().splitlines()
        entries = [line.split('|', 1) for line in out if '|' in line]
        if entries:
            ts, author = min(entries, key=lambda e: int(e[0]))
            return int(ts), author
    except Exception:
        pass
    return None

ZERO_SHA = '0' * 40

def get_changed_files(repo_root, event_name, base_ref, before_sha):
    if event_name == 'pull_request' and base_ref:
        diff_args = [f'origin/{base_ref}...HEAD']
    elif event_name != 'pull_request' and before_sha and before_sha != ZERO_SHA:
        diff_args = [before_sha, 'HEAD']
    else:
        return None
    try:
        out = subprocess.run(
            ['git', '-C', repo_root, 'diff', '--name-only', '--diff-filter=ACMR', '-z', *diff_args],
            capture_output=True, text=True, check=True, timeout=60
        ).stdout
    except Exception as e:
        print(f"WARNING: cannot determine changed files ({e}); falling back to full scan.")
        return None
    return {os.path.normpath(os.path.join(repo_root, f)) for f in out.split('\0') if f}

def describe_files(paths, repo_root, changed=None):
    """Строки вывода для группы совпадающих файлов: от самого раннего к самому позднему.
    Дата берётся из git (mtime после checkout в CI одинаков у всех файлов и ничего не значит)."""
    items = []
    for p in paths:
        info = first_commit_info(p, repo_root)
        if info:
            ts, author = info
            label = f"first commit {datetime.fromtimestamp(ts, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC, author: {author}"
        else:
            ts = int(os.path.getmtime(p))
            label = f"no git history, mtime {datetime.fromtimestamp(ts, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC"
        if changed is not None and os.path.normpath(p) in changed:
            label += ", changed in this push/PR"
        items.append((ts, p, label))
    return [f"   {p} ({label})" for _, p, label in sorted(items)]

def write_to_github_summary(message: str):
    summary_file = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary_file:
        with open(summary_file, 'a', encoding='utf-8') as sf:
            sf.write(message + '\n')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root")
    parser.add_argument("--actor", default="", help="GitHub actor who triggered the workflow")
    parser.add_argument("--owner", default="", help="Repository owner username")
    parser.add_argument("--event-name", default="", help="GitHub event name (push / pull_request)")
    parser.add_argument("--base-ref", default="", help="Base branch of the pull request")
    parser.add_argument("--before-sha", default="", help="Commit SHA before the push")
    parser.add_argument("--all", action="store_true", help="Check all files instead of only changed ones")
    args = parser.parse_args()

    # Skip if the push is made by me
    if args.actor and args.owner and args.actor.lower() == args.owner.lower():
        print("Workflow triggered by repository owner. Plagiarism check skipped.")
        sys.exit(0)

    print("Starting combined CI plagiarism analysis (EIL v1.1)...")
    violation_found = False

    changed = None if args.all else get_changed_files(
        args.repo_root, args.event_name, args.base_ref, args.before_sha)
    if changed is None:
        print("Mode: full scan of all files.")
    else:
        print(f"Mode: only files added/modified in this push/PR ({len(changed)}).")
        if not changed:
            print("No added or modified files (e.g. deletion only). Nothing to check.")
            sys.exit(0)

    def is_changed(path):
        return changed is None or os.path.normpath(path) in changed

    target_paths = []
    for root, dirs, _ in os.walk(args.repo_root):
        if any(p in root for p in ['.git', '.github', '.vscode', 'TESTS', 'UTILS', 'central-tools']):
            continue
        if os.path.basename(root) in TARGET_FOLDERS:
            for sub_dir in dirs:
                target_paths.append(os.path.join(root, sub_dir))

    for target_path in target_paths:
        if changed is not None:
            prefix = os.path.normpath(target_path) + os.sep
            if not any(c.startswith(prefix) for c in changed):
                continue

        parent = os.path.dirname(target_path)
        grandparent = os.path.dirname(parent)
        examples_path = os.path.join(grandparent, 'EXAMPLES')

        lecture_exact = {}
        lecture_logic = {}
        if os.path.isdir(examples_path):
            lecture_exact, lecture_logic = scan_folder(examples_path)

        student_exact, student_logic = scan_folder(target_path)

        exact_groups = defaultdict(list)
        logic_groups = defaultdict(list)

        for s_path in sorted(set(student_exact) | set(student_logic)):
            s_exact = student_exact.get(s_path)
            s_logic = student_logic.get(s_path)

            if s_exact:
                for l_path, l_exact in (lecture_exact.items() if is_changed(s_path) else ()):
                    if s_exact == l_exact:
                        print("CRITICAL EIL v1.1 VIOLATION: Functions copied from instructor examples!")
                        print(f"Student file: {s_path}\nLecture file: {l_path}\n")
                        violation_found = True
                exact_groups[s_exact].append(s_path)

            if s_logic:
                for l_path, l_logic in (lecture_logic.items() if is_changed(s_path) else ()):
                    if s_logic == l_logic:
                        print("CRITICAL EIL v1.1 VIOLATION: Logic structure copied from instructor examples!")
                        print(f"Student file: {s_path}\nLecture file: {l_path}\n")
                        violation_found = True
                logic_groups[s_logic].append(s_path)

        for sig, paths in exact_groups.items():
            if len(paths) > 1 and any(is_changed(p) for p in paths):
                print(f"PLAGIARISM DETECTED (Exact function match) in folder {target_path}:")
                for line in describe_files(paths, args.repo_root, changed):
                    print(line)
                print("-" * 50)
                violation_found = True

        for sig, paths in logic_groups.items():
            if len(paths) > 1 and any(is_changed(p) for p in paths):
                print(f"PLAGIARISM DETECTED (Logic match with token substitution) in folder {target_path}:")
                for line in describe_files(paths, args.repo_root, changed):
                    print(line)
                print("-" * 50)
                violation_found = True

    if violation_found:
        print("Analysis finished. Violations detected.")
        write_to_github_summary("Educational Integrity License (EIL) v1.1 violation detected.")
        sys.exit(1)
    else:
        print("Analysis finished. No violations found.")
        sys.exit(0)

if __name__ == "__main__":
    main()