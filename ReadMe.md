# CI Tools for Student Works

A collection of shared Continuous Integration (CI) scripts, GitHub Actions workflows, and utilities designed to automate the validation, testing, and plagiarism detection of student homework submissions.

## Features

- **Automated Homework Checking**: Pre-configured GitHub Actions workflows to test student submissions automatically upon push or pull request.
- **Containerized Testing**: Support for running homework tests in isolated Docker containers to ensure a consistent and fair evaluation environment.
- **Plagiarism Detection**: Integrated Python utilities to scan and flag potential code similarity across multiple submissions.
- **Code Style Validation**: Shell scripts to enforce coding standards and style guidelines automatically.
- **Smart Change Detection**: Scripts to identify only the modified files in a commit/PR, optimizing CI pipeline runtime.
- **Automated Reporting**: Generation of structured test and validation reports for easy review by instructors.

## Repository Structure

- **`.github/workflows/`**: Reusable GitHub Actions workflows:
  - `shared_hw_checker.yml`: Basic homework validation workflow.
  - `shared_hw_container_checker.yml`: Advanced workflow for testing submissions inside isolated containers.
  - `shared_plagiarism_hunter.yml`: Automated pipeline for detecting code plagiarism.
- **`SCRIPTS/`**: Shell scripts for local or CI execution:
  - `check_style.sh`: Validates code style and formatting.
  - `find_changed_files.sh`: Identifies modified files to optimize test execution.
  - `generate_report.sh`: Compiles test results into a readable summary report.
  - `run_homework_tests.sh`: Executes the core test suite for assignments.
  - `test_submission.sh`: Wrapper script for end-to-end submission testing.
- **`UTILS/`**: Python utilities:
  - `ci_plagiarism_hunter.py`: Core logic for detecting code similarity and plagiarism.

## Usage

### For Instructors
1. Copy the desired workflow files from `.github/workflows/` into your repository's `.github/workflows/` directory.
2. Adjust environment variables, paths, or test commands in the YAML files to match your specific assignment structure.
3. Reference or call the scripts in `SCRIPTS/` and `UTILS/` directly from your workflows or local grading environment.

### For Students
These tools are designed to run automatically on your pushes or pull requests, providing immediate feedback on your submission's correctness, style, and originality before final grading.

## License

This project is distributed under a **Custom Educational & Production License**. 

**Summary of Terms:**
- **Allowed**: Use in production environments, commercial applications, and personal "pet" projects without restriction.
- **Prohibited**: Use by students to complete, copy, simulate, or bypass laboratory works, practical assignments, homework, or any other form of graded academic coursework. 

For the full legal text and consequences of violation, please refer to the `LICENSE` file in this repository.