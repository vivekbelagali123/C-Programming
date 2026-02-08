public class array {
    public static void main(String []args){
        int arr[]={10,800,15000,90,10,2500};
        int max=arr[0];
        for(int i = 0;i < arr.length; i++) {
            if(arr[i] < max)
                max =arr[i];
                
        }
        System.out.println(max);
    }
}
        