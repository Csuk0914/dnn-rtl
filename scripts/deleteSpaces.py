f = open('train_input.dat','rb')
f2 = open('xx.dat','wb')
i= 0
for line in f:
    i+=1
    print i
    if i%10000==0:
        print i
    if i==49998:
        print i
    clean = ''
    for c in line:
        if c!=' ': clean += c
    f2.write(clean)