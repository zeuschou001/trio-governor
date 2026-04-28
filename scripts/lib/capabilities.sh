#!/usr/bin/env bash

capability_for_phase() {
  case "$1" in
    office-hours) printf 'discovery\n' ;;
    plan-ceo-review) printf 'product-review\n' ;;
    plan-eng-review) printf 'architecture-review\n' ;;
    writing-plans|quick-writing-plans) printf 'planning\n' ;;
    executing-plans|quick-executing-plans) printf 'execution\n' ;;
    verification-before-completion|quick-verification-before-completion) printf 'verification\n' ;;
    qa) printf 'qa\n' ;;
    finishing-a-development-branch) printf 'finish\n' ;;
    state-sync) printf 'state-sync\n' ;;
    *) printf '%s\n' '-' ;;
  esac
}

capability_dialogue_fallback_allowed() {
  case "$1" in
    discovery|product-review|architecture-review|qa) return 0 ;;
    *) return 1 ;;
  esac
}

capability_executor_for_phase() {
  local phase="$1" adapter_mode="$2" capability=''
  capability="$(capability_for_phase "$phase")"
  case "$phase" in
    state-sync)
      printf 'runtime\n'
      ;;
    *)
      if capability_dialogue_fallback_allowed "$capability" && [ "$adapter_mode" != 'full' ]; then
        printf 'dialogue\n'
      else
        printf 'adapter\n'
      fi
      ;;
  esac
}
