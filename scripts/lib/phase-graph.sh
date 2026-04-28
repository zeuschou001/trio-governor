#!/usr/bin/env bash

phase_initial_for_mode() {
  case "$1" in
    dev) printf 'office-hours\n' ;;
    quick) printf 'quick-writing-plans\n' ;;
    *) return 1 ;;
  esac
}

phase_terminal_for_mode() {
  case "$1" in
    dev) printf 'finishing-a-development-branch\n' ;;
    quick) printf 'quick-verification-before-completion\n' ;;
    *) return 1 ;;
  esac
}

phase_mode_for() {
  case "$1" in
    office-hours|plan-ceo-review|plan-eng-review|state-sync|writing-plans|executing-plans|verification-before-completion|qa|finishing-a-development-branch)
      printf 'dev\n'
      ;;
    quick-writing-plans|quick-executing-plans|quick-verification-before-completion)
      printf 'quick\n'
      ;;
    *)
      return 1
      ;;
  esac
}

phase_is_valid() {
  phase_mode_for "$1" >/dev/null
}

phase_is_optional() {
  [ "$1" = 'plan-ceo-review' ]
}

phase_can_transition_to() {
  case "$1:$2" in
    office-hours:plan-ceo-review|office-hours:plan-eng-review|plan-ceo-review:plan-eng-review|plan-eng-review:state-sync|state-sync:writing-plans|writing-plans:executing-plans|executing-plans:verification-before-completion|verification-before-completion:qa|qa:finishing-a-development-branch|quick-writing-plans:quick-executing-plans|quick-executing-plans:quick-verification-before-completion)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

phase_next_after() {
  case "$1" in
    office-hours) printf 'plan-ceo-review\n' ;;
    plan-ceo-review) printf 'plan-eng-review\n' ;;
    plan-eng-review) printf 'state-sync\n' ;;
    state-sync) printf 'writing-plans\n' ;;
    writing-plans) printf 'executing-plans\n' ;;
    executing-plans) printf 'verification-before-completion\n' ;;
    verification-before-completion) printf 'qa\n' ;;
    qa) printf 'finishing-a-development-branch\n' ;;
    quick-writing-plans) printf 'quick-executing-plans\n' ;;
    quick-executing-plans) printf 'quick-verification-before-completion\n' ;;
    finishing-a-development-branch|quick-verification-before-completion)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}
