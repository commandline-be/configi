CLEAN+= clean_modules

modules/lib%.a: modules/%.o $(LINIT_T)
	$(ECHOT) [AR] $@
	$(AR) $(ARFLAGS) $@ $< >/dev/null 2>&1
	$(RANLIB) $@

modules/%.o: modules/%.c $(LINIT_T)
	$(ECHOT) [CC] $@
	$(CC) -o $@ $(DEFINES) $(INCLUDES) $(CCWARN) $(CFLAGS) $(CCOPT) -c $<

modules/%.c: modules/%.luac $(LUAC2C_T)
	@$(LUAC2C_T) -n module_$(*F) -o $@ $<

modules/%.luac: modules/%.lua $(LUAC_T)
	@$(LUAC) $(LUACFLAGS) -o $@ $<

clean_modules:
	$(RM) $(RMFLAGS) modules/*.luac modules/*.a modules/*.c modules/*.o

.PHONY: clean_modules