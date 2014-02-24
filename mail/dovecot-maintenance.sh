#!/bin/sh

doveadm expunge -A mailbox Spam savedbefore 7d
doveadm expunge -A mailbox Trash savedbefore 28d

doveadm quota recalc