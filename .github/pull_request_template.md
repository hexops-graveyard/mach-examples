

## Checklist BEFORE PR
- [ ] Make sure you are using the correct [Zig version](https://github.com/hexops/mach#supported-zig-version)
- [ ] Run `zig fmt .` or `zig fmt path/to/file_changes`
- [ ] Check if code follows [zig style guide](https://ziglang.org/documentation/master/#Style-Guide)
- [ ] Prefix your commits & PR with e.g. 'core: example-name: description' format
- [ ] By selecting this checkbox, I agree to license my contributions to this project under the license(s) described in the LICENSE file, and I have the right to do so or have received permission to do so by an employer or client I am producing work for whom has this right.



## Checklist AFTER PR

- [ ] Update your fork to the latest main

```
git remote add upstream /url/to/original/repo
git fetch upstream
git checkout main
git reset --hard upstream/main  
git push origin main --force
```