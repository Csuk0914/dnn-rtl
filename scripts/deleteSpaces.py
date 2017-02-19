# Just a quick script used to delete spaces from train_input_spaced to get train_input
# Needs improvements to file paths... I didn'bother coz this file is essentially a one-timer and it has served its purpose

f = open('train_input_spaced.dat','rb')
f2 = open('train_input.dat','wb')
i= 0
for line in f:
    i+=1 #track progress
    print i
    clean = ''
    for c in line:
        if c!=' ': clean += c
    f2.write(clean)
