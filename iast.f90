module mod_random
! module for pseudo random numbers
 implicit none
 private
 public init_random_seed, randreal, randint
contains
 subroutine init_random_seed()
  use iso_fortran_env, only: int64
  implicit none
  integer, allocatable :: seed(:)
  integer :: i, n, un, istat, dt(8), pid
  integer(int64) :: t
  call random_seed(size=n)
  allocate(seed(n))
  ! First try if the OS provides a random number generator
  open(newunit=un, file="/dev/urandom", access="stream", &
  form="unformatted", action="read", status="old", iostat=istat)
  if (istat == 0) then
   read(un) seed
  close(un)
  else
  ! Fallback to XOR:ing the current time and pid. The PID is useful in case one launches multiple instances of the same program in parallel.
   call system_clock(t)
   if (t == 0) then
    call date_and_time(values=dt)
    t = (dt(1) - 1970) * 365_int64 * 24 * 60 * 60 * 1000 &
      + dt(2) * 31_int64 * 24 * 60 * 60 * 1000 &
      + dt(3) * 24_int64 * 60 * 60 * 1000 &
      + dt(5) * 60 * 60 * 1000 &
      + dt(6) * 60 * 1000 + dt(7) * 1000 &
      + dt(8)
   end if
   pid = getpid()
   t = ieor(t, int(pid, kind(t)))
   do i = 1, n
    seed(i) = lcg(t)
   end do
  end if
  call random_seed(put=seed)
 contains
 ! This simple PRNG might not be good enough for real work, but is sufficient for seeding a better PRNG.
  function lcg(s)
   integer :: lcg
   integer(int64) :: s
   if (s == 0) then
    s = 104729
   else
   s = mod(s, 4294967296_int64)
   end if
   s = mod(s * 279470273_int64, 4294967291_int64)
   lcg = int(mod(s, int(huge(0), int64)), kind(0))
  end function
 end subroutine
    ! Random real (0.0 <= r < 1.0)
 real function randreal()
  call random_number(randreal)
 end function
 ! Random int (a <= r <= b)
 integer function randint(a, b)
  integer, intent(in) :: a, b
  if (a > b) stop "a must be less than or equal to b"
   randint = a + int(randreal() * (b - a + 1))
  end function
end module
!
program iast_GA
 ! IAST program
 use mod_random
 implicit none
 real             :: comp,concx1,concx2,concy1,concy2
 real             :: tol = 0.001
 real             :: temperature = 298.0
 real             :: h1,h2,p,presion1,presion2,n,n1,n2
 real             :: inferior,superior
 real             :: s1 = 0.0,s2 = 0.0,x0
 integer          :: err_apertura = 0,i,ii,k,l,j,intervalos,npar
 integer          :: GA_POPSIZE =  1
 integer          :: ncomponents = 2
 character(100)   :: line,ajuste,test_name,intmethod = 'Trapezes' ! Simpsons, Trapezes
 character(5)     :: inpt
 real,allocatable :: x1(:),y1(:),x2(:),y2(:),coef1(:),coef2(:),PI1(:),PI2(:),area1(:),area2(:)
 real,allocatable :: e_coef1(:),e_coef2(:),param(:,:),eparam(:,:)
 real,allocatable :: puntos1(:),puntos2(:),funcion1(:),funcion2(:)
 logical          :: flag = .true.
 
 call init_random_seed()
 read_input: do
  read(5,'(A)',iostat=err_apertura)line
  if ( err_apertura /= 0 ) exit read_input
  if(line(1:5)=='model')then
   read(line,*)inpt,ajuste
   call MakeInitPOP(ajuste,npar,GA_POPSIZE)
   allocate(param(ncomponents,0:npar-1),eparam(ncomponents,0:npar-1))
   allocate(coef1(0:npar-1),coef2(0:npar-1),e_coef1(0:npar-1),e_coef2(0:npar-1))
  end if
  if(line(1:5)=='ffit?') read(line,*)inpt,flag
  if(flag.eqv..false.)then
   write(6,*)'Fit is already done'
   readparameter: do ii=1,ncomponents
    if(ncomponents>=3) stop "[ERROR] Uh Oh: you're screwed"
    read(5,*)(param(ii,j),j=0,npar-1)
   end do readparameter
  end if
  if(line(1:5)=='inter') read(line,*)inpt,intervalos
  if(line(1:5)=='toler') read(line,*)inpt,tol
  if(line(1:5)=='tempe') read(line,*)inpt,temperature
  if(line(1:5)=='ncomp')then
   read(line,*)inpt,ncomponents
  !do ii =1,ncomponents
   read(5,*)concy1
   read(5,*)concy2
  !end do
  end if
  if(line(1:5)=='InteM') read(line,*)inpt,intmethod
  if(err_apertura/=0) exit read_input
 end do read_input
 !
 nisothermpure: do ii=1,ncomponents
  write (test_name, '( "isoterma", I1, ".dat" )' ) ii
  call system ("cp " // test_name // " isotermaN.dat")
  open(unit=100,file="isotermaN.dat",status='old',iostat=err_apertura)
  if(err_apertura/=0) stop '[ERROR] isotermaN.dat :  Catastrophic failure'
  k=0 
  do0: do
   READ (100,'(A)',IOSTAT=err_apertura) line 
   IF( err_apertura /= 0 ) EXIT do0
   k=k+1
  END DO do0
  if(ii==1) allocate(x1(1:k),y1(1:k))
  if(ii>=2) allocate(x2(1:k),y2(1:k))
  rewind(100)
  do1: do i=1,k
   read (100,'(A)',IOSTAT=err_apertura) line
   if(err_apertura/=0) EXIT do1
   if(ii==1)read(line,*) x1(i),y1(i)
   if(ii>=2)read(line,*) x2(i),y2(i)
  end do do1
  close(100)
 end do nisothermpure
 if(flag)then
  do i=1,ncomponents
   coef1=0
   coef2=0
   write(test_name, '( "isoterma", I1, ".dat" )' ) i
   write(6, '( "Fitting isoterma", I1, ".dat" )' ) i
   write(6,'("Isotherm model: ",A)') ajuste 
   call system ("cp " // test_name // " isotermaN.dat")
   call fitgen(coef1,e_coef1,npar,ajuste,GA_POPSIZE,temperature)
   do j=0,npar-1
    param(i,j)=coef1(j)
    eparam(i,j)=e_coef1(j)
   end do
  end do
 !else
 ! readparameter: do ii=1,ncomponents
 !  read(5,*)(param(ii,j),j=0,npar-1)
 ! end do readparameter
 ! !write(6,*)'Citizen Elitist: ,',0,'Fitness: ',cost(a,x,y,n,dimen,funk,T)
 end if
 do j=0,npar-1
  coef1(j)=param(1,j)
  coef2(j)=param(2,j)
  e_coef1(j)=eparam(1,j)
  e_coef2(j)=eparam(2,j)
 end do
 deallocate(param,eparam)
 
!========================================================================
! CALCULO DE  AREAS
!========================================================================
 l=size(x2)
 k=size(x1)
 allocate(puntos1(0:intervalos),puntos2(0:intervalos))
  IF (x1(1)<x2(1)) THEN
   inferior =log10(x1(1))
  ELSE
   inferior =log10(x2(1))
  END IF
  IF (x1(k)<x2(l)) THEN
   superior =log10(x2(l))
  ELSE
   superior =log10(x1(k))
  END IF
  h1 = real((superior-inferior)/intervalos)
  DO i=0,intervalos
   puntos1(i)=10**(inferior+i*h1) 
  END DO
  IF (x1(1)<x2(1)) THEN
   inferior =log10(x1(1))
  ELSE
   inferior =log10(x2(1))
  END IF
  IF (x1(k)<x2(l)) THEN
   superior =log10(x2(l))
  ELSE
   superior =log10(x1(k))
  END IF
  h2 = real((superior-inferior)/intervalos)
  DO i=0,intervalos
   puntos2(i)=10**(inferior+i*h2)
  END DO
 allocate(funcion1(0:intervalos),funcion2(0:intervalos))
 do i=0,intervalos
  x0 = puntos1(i)
  funcion1(i) = model(coef1,x0,npar,ajuste,temperature)
  x0 = puntos2(i)
  funcion2(i) = model(coef2,x0,npar,ajuste,temperature)
 end do
 if(intmethod=='Simpsons')then
  allocate(pi1(0:intervalos),pi2(0:intervalos))
  do i=0,intervalos
   concx1 = 10.0**(inferior+i*h1)
   concx2 = 10.0**(inferior+(i+1)*h1)
   s1 = s1 + Integrate(concx1,concx2,25,coef1,npar,ajuste,temperature)
   concx1 = 10.0**(inferior+i*h2)
   concx2 = 10.0**(inferior+(i+1)*h2)
   s2 = s2 + Integrate(concx1,concx2,25,coef2,npar,ajuste,temperature)
   pi1(i) = s1
   pi2(i) = s2
  end do
 else if(intmethod=='Trapezes')then
  allocate(area1(0:intervalos),area2(0:intervalos),PI1(0:intervalos),PI2(0:intervalos))
  do i=0,intervalos-1
   area1(i)= real((funcion1(i)+funcion1(i+1))*h1/2)
   area2(i)= real((funcion2(i)+funcion2(i+1))*h2/2)
   s1 = s1 + area1(i)
   s2 = s2 + area2(i)
   PI1(i+1)= s1
   PI2(i+1)= s2
  end do
 else
  stop 'Choose a integration method "intmethod"'
 end if
 OPEN(221,file='iso1.dat')
 OPEN(222,file='iso2.dat')
 do i=1,intervalos
  WRITE(221,*)puntos1(i),funcion1(i),pi1(i)
  WRITE(222,*)puntos2(i),funcion2(i),pi2(i)
 end do
 close(221)
 close(222)
 
!========================================================================
! IAST (binary mixture)
!========================================================================
 open(unit=104,file='adsorcion.dat')
 do i=1,intervalos
  do j=1,intervalos
    comp = abs(PI1(i)-PI2(j))           ! las presiones se igualan
    if (comp <= tol) then              ! ...
     if (abs(x1(1)-x1(k))>100) then
      presion1 = 10**(inferior+i*h1)
     else
      presion1 = inferior+i+h1
     end if
     if (abs(x2(1)-x2(l))>100) then
      presion2 = 10**(inferior+j*h2)
     else
      presion2 = inferior+j*h2
     end if
     ! ... concentraciones ( 2 componentes )
      concx1 = presion2*concy1 / (concy2*presion1 + concy1*presion2)
      concx2 = 1.0 - concx1
     ! ... presion total y loading
      p = presion1*concx1/concy1
      n1 = funcion1(i)*concx1
      n2 = funcion2(j)*concx2
      n = n1+n2
      write(104,*)p,n1,n2,n
     end if
  end do
 end do
 close(104)
 !call system ("awk '{print $1,$2,$3,$4}' adsorcion.dat | sort -gk1 > c")
 !call system ("mv c adsorcion.dat")
 deallocate(puntos1,puntos2,pi1,pi2,funcion1,funcion2)
 stop 'IAST finish'
 contains
!
 subroutine MakeInitPOP(funk,n,POPSIZE)
 implicit none
 character(100),intent(in)::  funk
 integer,intent(out)::        n,POPSIZE
 select case (ajuste)
  case("freundlich")
   n= 2                   ! numero de parametros del modelo.
   POPSIZE = 2**14        ! tamaño de genoma: aumentarlo incrementa la probabilidad de alcanzar un valor optimo,
  case ("langmuir")       ! pero tiene un alto coste computacional
   n=2
   POPSIZE = 2**16
  case ("toth")
   n=3
   POPSIZE = 2**18
  case ("jensen")
   n=4
   POPSIZE = 2**23
  case ("dubinin_raduschkevich")
   n=5
   POPSIZE = 2*23
  case ("langmuir_dualsite")
   n=4
   POPSIZE = 2**18
  case ("dubinin_astakhov")
   n=5
   POPSIZE = 2**15
 end select
 return
 end subroutine MakeInitPOP
! 
 subroutine fitgen(a,ea,n,funk,GA_POPSIZE,T)
! crea un vector de valores posibles de ajuste y va mezclando 'genes' para alcanzar
! un ajuste optimo minimizando el coste a una lectura de la isoterma
  implicit none
  integer                  ::  i,j,k,l,h,err_apertura,dimen
  integer,intent(in)       ::  GA_POPSIZE,n
  real,intent(in)          ::  T
  real,intent(out)         ::  a(0:n-1),ea(0:n-1)
  real                     ::  setparam(GA_POPSIZE,0:n-1),fit(GA_POPSIZE)
  real                     ::  f1,f2
  character(100)           ::  line
  character(100),intent(in)::  funk
  real,allocatable         ::  x(:),y(:)
  real,parameter           ::  mutationP0 = 0.25
  real,parameter           ::  tol = 1.0
  real,parameter           ::  max_range = 100.0
  real                     ::  mutationP, renorm = 0.0, suma = 0.0,rrr
  fit = 99999999.99
  open(unit=123,file='isotermaN.dat',iostat=err_apertura)
  if(err_apertura/=0)stop '[error] open file'
  l=0
  dofit0: do
   read(123,'(A)',iostat=err_apertura) line
   if(err_apertura/=0) exit dofit0
   l=l+1
  end do dofit0
  allocate(x(l),y(l))
  rewind(123)
  dofit1: do i=1,l
   read(123,'(A)',iostat=err_apertura) line
   if(err_apertura/=0) exit dofit1
   read(line,*) x(i),y(i)
   write(6,*) x(i),y(i)
  end do dofit1
  close(123)
  dimen=l
  h = 0
  a  = 0.0
  ea = 0.0
  init_set: do k=1,GA_POPSIZE
   do j=0,n-1
    if(j==0)setparam(k,j) = max_range*randreal()
    if(j>=1)setparam(k,j) = randreal()
    if(j==3)setparam(k,j) = max_range*randreal()
    if(j==4)setparam(k,j) = (minval(x)/2.0 + 2*maxval(x)*randreal())
    if(j==5)setparam(k,j) = max_range*randreal()
   end do
  end do init_set
  mix: do
   mutationP=mutationP0
   i = randint(1,GA_POPSIZE)
   j = randint(1,GA_POPSIZE)
   do while (i==j)
    j = randint(1,GA_POPSIZE)
   end do
   do k=0,n-1
    a(k) = setparam(i,k)
   end do
   f1 = cost(a,x,y,n,dimen,funk,T)
   do k=0,n-1
    a(k) = setparam(j,k)
    ea(k)= 0.0
   end do
   f2 = cost(a,x,y,n,dimen,funk,T)
   fit(i)=f1
   fit(j)=f2
   if (abs(f1 - f2) <= 0.0000001 ) then
      h = h + 1
      if ( h >= 1000 ) then
       exit mix
      end if
   end if
   renorm = f1*f2/(f1+f2)
   f1=renorm/f1
   f2=renorm/f2
   suma = 1.0/(f1+f2+mutationP)
   f1=f1*suma
   f2=f2*suma
   mutationP=mutationP*suma
   rrr = randreal()
   if(rrr<=f1)then
     do l=0,n-1 ! 2 <- 1
      setparam(j,l) = setparam(i,l)
     end do
   else if ( rrr > f1 .and. rrr<= f2 + f1 ) then
     do l=0,n-1 ! 1 <- 2
      setparam(i,l) = setparam(j,l)
     end do
   else
    k = randint(0,n-1) ! k-esima componente
    if(f1 <= f2) then  ! coste de i > coste de j
     forall (l=0:n-1)
      setparam(i,l) = setparam(j,l)
     end forall
     if(k==0)setparam(i,k) = max_range*randreal()
     if(k>=1)setparam(i,k) = randreal()
     if(k==3)setparam(i,k) = max_range*randreal()
     if(k==4)setparam(i,k) = (minval(x)/2.0 + 2*maxval(x)*randreal())
     if(k==5)setparam(i,k) = max_range*randreal()
    else
     forall (l=0:n-1)
      setparam(j,l) = setparam(i,l)
     end forall
     if(k==0)setparam(j,k) = max_range*randreal()
     if(k>=1)setparam(j,k) = randreal()
     if(k==3)setparam(j,k) = max_range*randreal()
     if(k==4)setparam(j,k) = (minval(x)/2.0 + 2*maxval(x)*randreal())
     if(k==5)setparam(j,k) = max_range*randreal()
    end if
   end if
  end do mix
  i = minloc(fit, dim=1)
  write(6,*)'Citizen Elitist:',i,'Fitness:',fit(i)
  !call sort_by_cost(q,n,setparam,fit,i)
  write(6,*)'Parameters:',(setparam(i,k),k=0,n-1), &
  'Deviations:',(sqrt( sum([((setparam(j,k)-a(k))**2,j=1,GA_POPSIZE)]) &
  / real(GA_POPSIZE-1) ),k=0,n-1)
  do k=0,n-1
   a(k) = setparam(i,k)
   ea(k)= sqrt( sum([((setparam(j,k)-a(k))**2,j=1,GA_POPSIZE)])/real(GA_POPSIZE-1) )
  end do
  return
  deallocate(x,y)
 end subroutine fitgen
! ...
 subroutine sort_by_cost(q,n,setparam,fit,k)
 implicit none
 integer,intent(in) :: q,n
 integer            :: i
 integer,intent(out):: k
 real               :: fit(q)
 real,intent(in)    :: setparam(q,0:n-1)
 real               :: current_fit = 9999999.9
 do i=1,size(fit)
  if(fit(i)<=current_fit)then
   current_fit=fit(i)
   k=i
  end if
 end do
 end subroutine sort_by_cost
! ...
 real function cost(a,x,y,n,l,function_,T)
! calcula el coste
  implicit none
  integer,intent(in)        ::  n,l
  real,intent(in)           ::  T
  integer                   ::  i = 0
  real,intent(in)           ::  a(0:n-1),x(l),y(l)
  real                      ::  funk(l)
  real                      ::  x0 = 0.0
  character(100),intent(in) ::  function_
  cost = 0.0
  funk = 0.0
  do i=1,l
   x0 = x(i)
   funk(i) = model(a,x0,n,function_,T)
   if (funk(i)<0.0) funk(i) = 0.0
  end do
  cost = sum([(abs(y(i)-funk(i))**2,i=1,l)])
  return
 end function cost
!
 real function model(a,x,n,function_,T)
  implicit none
  integer,intent(in)        :: n
  real,intent(in)           :: a(0:n-1)
  real,intent(in)           :: x
  character(100),intent(in) :: function_
  real,intent(in)           :: T
  real,parameter            :: R = 0.008314472 ! kJ / mol / K
  select case (function_)
   case("freundlich")!n = a*x**b #function #model
    model = a(0)*x**a(1)
   case ("langmuir") !n = nmax*alfa*P/(1+alfa*P) #function #model
    model = a(0)*a(1)*x/(1+a(1)*x)
   case ("toth")     !n=f(x)=Nmax*alfa*x/(1+(alfa*x)**c)**(1/c) #function #model
    model = (a(0)*a(1)*x)/((1.0+(a(1)*x)**a(2))**(1/a(2)))
   case ("jensen")   !n = k1*x/(1+(k1*x/(alfa*(1+k2*x))**c))**(1/c) #function #model
    model = a(0)*x/(1+(a(0)*x/(a(1)*(1+a(3)*x))**a(2)))**(1/a(2))
   case ("dubinin_raduschkevich") ! N=Nm*exp(-(RT/Eo ln(Po/P))^2)  #model
    model = a(0)*exp(-((R*T/a(3))*log(a(4)/x) )**2)
   case ("langmuir_dualsite")      ! N=Nm*b*P/(1+b*P) + Nn*c*P/(1+c*P) #model
    model = a(0)*a(1)*x/(1+a(1)*x) + a(3)*a(2)*x/(1+a(2)*x)
   case ("dubinin_astakhov")       ! N=Nm*exp(-(RT/Eo ln(Po/P))^d) #model
    model = a(0)*exp(-((R*T/a(3))*log(a(4)/x) )**a(1))
  end select
  return
 end function model
! ...
 real function integrate(x0,x1,integration_points,a,n,function_,T)
  implicit none
  integer              ::  i
  integer,intent(in)   ::  n,integration_points
  real                 ::  delta,x
  real,intent(in)      ::  x0,x1
  real                 ::  factor
  real,intent(in)      ::  a(0:n-1),T
  character(100),intent(in):: function_
  delta=(x1-x0)/(integration_points)
  area: do i = 0,integration_points
   factor = 1.0
   if (i==0.or.i==integration_points-1) factor = 3.0/8.0
   if (i==1.or.i==integration_points-2) factor = 7.0/6.0
   if (i==2.or.i==integration_points-3) factor = 23.0/24.0
   x = x0 + delta*(0.5+i)
   Integrate = Integrate + factor*delta*model(a,x,n,function_,T)/x
  end do area
  return
 end function integrate
end program iast_GA
